import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// Off-main owner for one immutable terminal activation cohort.
///
/// A fixed worker fleet performs bounded MainActor admissions. The scheduler
/// never derives terminal identity or reads mutable composition/topology state.
package actor TerminalActivationScheduler {
    private enum Lifecycle {
        case idle
        case activating
        case settled(TerminalActivationSettlement)
    }

    private enum MemberExecution {
        case queued(priority: TerminalActivationVisibilityPriority, attempt: Int)
        case attaching(priority: TerminalActivationVisibilityPriority, attempt: Int)
        case terminal(TerminalActivationTerminalOutcome)
    }

    private struct Member {
        let descriptor: TerminalActivationDescriptor
        let originalOrdinal: Int
        var execution: MemberExecution
    }

    private struct QueuedCandidate {
        let paneID: PaneId
        let priority: TerminalActivationVisibilityPriority
        let attempt: Int
        let originalOrdinal: Int
    }

    private let cohort: TerminalActivationCohort
    private let admissionPort: any TerminalActivationAdmissionPort
    private let releaseSignal: any TerminalActivationReleaseSignal
    private var lifecycle = Lifecycle.idle
    private var membersByPaneID: [PaneId: Member]
    private var activationWaiters: [CheckedContinuation<TerminalActivationSettlement, Never>] = []
    private var currentSimultaneousAdmissions = 0
    private var maximumSimultaneousAdmissions = 0
    private var workerCount = 0
    private var yieldCount = 0
    private var activationDeferralOutcome: StartupDeferralOutcome?
    /// The latest visibility revision this scheduler has applied. Every
    /// proposal carries it so the admission port can prove (G2) that any
    /// snapshot recorded before the proposal has already been applied here.
    /// Nothing in this generation of the scheduler advances it yet beyond its
    /// zero baseline; the App-owned visibility observation that mints later
    /// revisions is wired in a later slice.
    private var appliedVisibilityRevision: TerminalVisibilityRevision

    package init(
        cohort: TerminalActivationCohort,
        admissionPort: any TerminalActivationAdmissionPort,
        releaseSignal: any TerminalActivationReleaseSignal = TerminalActivationReleaseGate(
            isReleased: true
        )
    ) {
        let paneIDs = cohort.input.entries.map(\.paneID)
        precondition(Set(paneIDs).count == paneIDs.count, "terminal activation cohort contains duplicate panes")

        self.cohort = cohort
        self.admissionPort = admissionPort
        self.releaseSignal = releaseSignal
        appliedVisibilityRevision = TerminalVisibilityRevision(generation: cohort.generation, ordinal: 0)
        membersByPaneID = Dictionary(
            uniqueKeysWithValues: cohort.input.entries.enumerated().map { ordinal, descriptor in
                (
                    descriptor.paneID,
                    Member(
                        descriptor: descriptor,
                        originalOrdinal: ordinal,
                        execution: .queued(
                            priority: descriptor.visibilityPriority,
                            attempt: 1
                        )
                    )
                )
            }
        )
    }

    package func activate() async -> TerminalActivationSettlement {
        switch lifecycle {
        case .settled(let settlement):
            return settlement
        case .activating:
            return await withCheckedContinuation { continuation in
                activationWaiters.append(continuation)
            }
        case .idle:
            lifecycle = .activating
        }

        activationDeferralOutcome = await releaseSignal.waitUntilReleased()

        let maximumWorkerCount = min(
            membersByPaneID.count,
            AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions
        )
        workerCount = maximumWorkerCount

        await withTaskGroup(of: Void.self) { taskGroup in
            for _ in 0..<maximumWorkerCount {
                taskGroup.addTask {
                    await self.runWorker()
                }
            }
        }

        let settlement = makeSettlement()
        lifecycle = .settled(settlement)
        let waiters = activationWaiters
        activationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: settlement)
        }
        return settlement
    }

    package func recordedActivationDeferralOutcome() -> StartupDeferralOutcome? {
        activationDeferralOutcome
    }

    func memberState(for paneID: PaneId) -> TerminalActivationMemberState? {
        guard let execution = membersByPaneID[paneID]?.execution else { return nil }
        return publicState(for: execution)
    }

    func diagnostics() -> TerminalActivationSchedulerDiagnostics {
        TerminalActivationSchedulerDiagnostics(
            currentSimultaneousAdmissions: currentSimultaneousAdmissions,
            maximumSimultaneousAdmissions: maximumSimultaneousAdmissions,
            workerCount: workerCount,
            yieldCount: yieldCount
        )
    }

    func cancelAndReplace(
        with replacement: WorkspaceContentMountGeneration
    ) {
        precondition(replacement != cohort.generation, "replacement activation generation must differ")

        for (paneID, var member) in membersByPaneID {
            switch member.execution {
            case .queued, .attaching:
                member.execution = .terminal(.cancelledReplaced(replacement: replacement))
                membersByPaneID[paneID] = member
            case .terminal:
                break
            }
        }

        if case .idle = lifecycle {
            lifecycle = .settled(makeSettlement())
        }
    }

    package func promote(
        paneID: PaneId,
        to priority: TerminalActivationVisibilityPriority
    ) -> TerminalActivationPromotionResult {
        guard var member = membersByPaneID[paneID] else { return .paneNotFound }
        switch member.execution {
        case .queued(let currentPriority, let attempt):
            guard currentPriority != priority else { return .unchanged(priority: priority) }
            member.execution = .queued(priority: priority, attempt: attempt)
            membersByPaneID[paneID] = member
            return .promoted(from: currentPriority, to: priority)
        case .attaching, .terminal:
            return .memberNotQueued(state: publicState(for: member.execution))
        }
    }

    /// Proposes, claims, marks attaching, and activates one candidate at a
    /// time until no queued member remains. `AppPolicies.TerminalActivation
    /// .restoreMaximumConcurrentAdmissions == 1` means `activate()` spawns at
    /// most one worker, so `nextQueuedCandidate()`'s pure selection can never
    /// race a concurrent `markAttaching(_:)` mutation from another worker.
    private func runWorker() async {
        while let candidate = nextQueuedCandidate() {
            let proposal = TerminalAdmissionProposal(
                generation: cohort.generation,
                paneID: candidate.paneID,
                attempt: candidate.attempt,
                appliedVisibilityRevision: appliedVisibilityRevision
            )
            let outcome = await admissionPort.claimPreparedTerminal(proposal)
            switch outcome {
            case .claimed(let claim):
                // No `await` between claim receipt and marking attaching: the
                // admission counter must reflect only claims the port granted.
                markAttaching(candidate)
                let activationOutcome = await admissionPort.activateClaimedTerminal(claim)
                complete(paneID: candidate.paneID, attempt: candidate.attempt, with: activationOutcome)
                yieldCount += 1
                await Task.yield()
            case .visibilityChanged(let snapshot):
                appliedVisibilityRevision = snapshot.revision
            case .rejected(let rejection):
                resolveRejectedProposal(paneID: candidate.paneID, attempt: candidate.attempt, rejection: rejection)
            }
        }
    }

    /// Pure selection: the highest-ranked queued member, or nil. Performs no
    /// mutation, so a caller may inspect the candidate before deciding whether
    /// a claim was actually granted.
    private func nextQueuedCandidate() -> QueuedCandidate? {
        membersByPaneID.values.compactMap { member -> QueuedCandidate? in
            guard case .queued(let priority, let attempt) = member.execution else { return nil }
            return QueuedCandidate(
                paneID: member.descriptor.paneID,
                priority: priority,
                attempt: attempt,
                originalOrdinal: member.originalOrdinal
            )
        }.min { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.originalOrdinal < rhs.originalOrdinal
            }
            return lhs.priority < rhs.priority
        }
    }

    /// Moves a claimed candidate to `attaching` and only now counts it toward
    /// the simultaneous-admission bound. Called exactly once per granted claim.
    private func markAttaching(_ candidate: QueuedCandidate) {
        guard var member = membersByPaneID[candidate.paneID] else { return }
        member.execution = .attaching(priority: candidate.priority, attempt: candidate.attempt)
        membersByPaneID[candidate.paneID] = member
        currentSimultaneousAdmissions += 1
        maximumSimultaneousAdmissions = max(
            maximumSimultaneousAdmissions,
            currentSimultaneousAdmissions
        )
    }

    private func complete(
        paneID: PaneId,
        attempt: Int,
        with outcome: ClaimedTerminalActivationOutcome
    ) {
        precondition(currentSimultaneousAdmissions > 0, "terminal activation admission count underflow")
        currentSimultaneousAdmissions -= 1

        guard var member = membersByPaneID[paneID] else { return }
        guard
            case .attaching(let priority, let memberAttempt) = member.execution,
            memberAttempt == attempt
        else {
            return
        }

        switch outcome {
        case .attempted(let result):
            switch result {
            case .ready(let surfaceID):
                member.execution = .terminal(.ready(surfaceID: surfaceID))
            case .failed(let failure, .doNotRetry):
                member.execution = .terminal(
                    .failedTerminal(
                        failure: failure,
                        retry: .notRequested(attemptCount: attempt)
                    )
                )
            case .failed(let failure, .retry):
                if attempt == 1 {
                    member.execution = .queued(priority: priority, attempt: 2)
                } else {
                    member.execution = .terminal(
                        .failedTerminal(
                            failure: failure,
                            retry: .exhausted(attemptCount: attempt)
                        )
                    )
                }
            }
        case .rejected(let rejection):
            // Defensive: the port refused to activate a claim this scheduler
            // just received. Resolve exactly like a non-retryable failure.
            member.execution = .terminal(
                .failedTerminal(
                    failure: activationRejectionFailure(rejection),
                    retry: .notRequested(attemptCount: attempt)
                )
            )
        }
        membersByPaneID[paneID] = member
    }

    /// A `.rejected` claim outcome resolves the member exactly as `complete`
    /// resolves a `.doNotRetry` failure: no second attempt is made.
    private func resolveRejectedProposal(
        paneID: PaneId,
        attempt: Int,
        rejection: TerminalAdmissionClaimRejection
    ) {
        guard var member = membersByPaneID[paneID] else { return }
        guard
            case .queued(_, let memberAttempt) = member.execution,
            memberAttempt == attempt
        else {
            return
        }
        member.execution = .terminal(
            .failedTerminal(
                failure: claimRejectionFailure(rejection),
                retry: .notRequested(attemptCount: attempt)
            )
        )
        membersByPaneID[paneID] = member
    }

    private func claimRejectionFailure(_ rejection: TerminalAdmissionClaimRejection) -> TerminalActivationFailure {
        switch rejection {
        case .staleGeneration:
            return .attachmentRejected(code: "stale_generation")
        case .paneNotInCohort:
            return .attachmentRejected(code: "pane_not_in_cohort")
        case .trustedFrameUnavailable:
            return .attachmentRejected(code: "trusted_frame_unavailable")
        case .custodyUnavailableForClaim:
            return .attachmentRejected(code: "custody_unavailable_for_claim")
        case .retryClaimMismatch:
            return .attachmentRejected(code: "retry_claim_mismatch")
        }
    }

    private func activationRejectionFailure(
        _ rejection: ClaimedTerminalActivationRejection
    ) -> TerminalActivationFailure {
        switch rejection {
        case .claimAlreadyConsumed:
            return .attachmentRejected(code: "claim_already_consumed")
        case .claimNotIssued:
            return .attachmentRejected(code: "claim_not_issued")
        }
    }

    private func publicState(for execution: MemberExecution) -> TerminalActivationMemberState {
        switch execution {
        case .queued(let priority, _):
            return .queued(priority: priority)
        case .attaching:
            return .attaching
        case .terminal(let outcome):
            switch outcome {
            case .ready(let surfaceID):
                return .ready(surfaceID: surfaceID)
            case .failedTerminal(let failure, let retry):
                return .failedTerminal(failure: failure, retry: retry)
            case .cancelledReplaced(let replacement):
                return .cancelledReplaced(replacement: replacement)
            }
        }
    }

    private func makeSettlement() -> TerminalActivationSettlement {
        let outcomesByPaneID = membersByPaneID.mapValues { member -> TerminalActivationTerminalOutcome in
            guard case .terminal(let outcome) = member.execution else {
                preconditionFailure("terminal activation cohort settled with unfinished members")
            }
            return outcome
        }
        return TerminalActivationSettlement(
            generation: cohort.generation,
            outcomesByPaneID: outcomesByPaneID
        )
    }
}
