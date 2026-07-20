import Foundation

/// Off-main owner for one immutable terminal activation cohort.
///
/// A fixed worker fleet performs bounded MainActor admissions. The scheduler
/// never derives terminal identity or reads mutable composition/topology state.
actor TerminalActivationScheduler {
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
    private var lifecycle = Lifecycle.idle
    private var membersByPaneID: [PaneId: Member]
    private var activationWaiters: [CheckedContinuation<TerminalActivationSettlement, Never>] = []
    private var currentSimultaneousAdmissions = 0
    private var maximumSimultaneousAdmissions = 0
    private var workerCount = 0

    init(
        cohort: TerminalActivationCohort,
        admissionPort: any TerminalActivationAdmissionPort
    ) {
        let paneIDs = cohort.input.entries.map(\.paneID)
        precondition(Set(paneIDs).count == paneIDs.count, "terminal activation cohort contains duplicate panes")

        self.cohort = cohort
        self.admissionPort = admissionPort
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

    func activate() async -> TerminalActivationSettlement {
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

        var initialAdmissions: [TerminalActivationAdmission] = []
        let maximumWorkerCount = min(
            membersByPaneID.count,
            AppPolicies.TerminalActivation.maximumConcurrentAdmissions
        )
        for _ in 0..<maximumWorkerCount {
            guard let admission = claimNextAdmission() else { break }
            initialAdmissions.append(admission)
        }
        workerCount = initialAdmissions.count

        await withTaskGroup(of: Void.self) { taskGroup in
            for admission in initialAdmissions {
                taskGroup.addTask {
                    await self.runWorker(startingWith: admission)
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

    func memberState(for paneID: PaneId) -> TerminalActivationMemberState? {
        guard let execution = membersByPaneID[paneID]?.execution else { return nil }
        return publicState(for: execution)
    }

    func diagnostics() -> TerminalActivationSchedulerDiagnostics {
        TerminalActivationSchedulerDiagnostics(
            currentSimultaneousAdmissions: currentSimultaneousAdmissions,
            maximumSimultaneousAdmissions: maximumSimultaneousAdmissions,
            workerCount: workerCount
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

    func promote(
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

    private func runWorker(startingWith initialAdmission: TerminalActivationAdmission) async {
        var nextAdmission: TerminalActivationAdmission? = initialAdmission
        while let admission = nextAdmission {
            let result = await admissionPort.activate(admission)
            complete(admission: admission, with: result)
            nextAdmission = claimNextAdmission()
        }
    }

    private func claimNextAdmission() -> TerminalActivationAdmission? {
        let candidate = membersByPaneID.values.compactMap { member -> QueuedCandidate? in
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

        guard let candidate, var member = membersByPaneID[candidate.paneID] else { return nil }
        member.execution = .attaching(
            priority: candidate.priority,
            attempt: candidate.attempt
        )
        membersByPaneID[candidate.paneID] = member
        currentSimultaneousAdmissions += 1
        maximumSimultaneousAdmissions = max(
            maximumSimultaneousAdmissions,
            currentSimultaneousAdmissions
        )
        return TerminalActivationAdmission(
            generation: cohort.generation,
            descriptor: member.descriptor,
            attempt: candidate.attempt
        )
    }

    private func complete(
        admission: TerminalActivationAdmission,
        with result: TerminalActivationAttemptResult
    ) {
        precondition(currentSimultaneousAdmissions > 0, "terminal activation admission count underflow")
        currentSimultaneousAdmissions -= 1

        guard var member = membersByPaneID[admission.descriptor.paneID] else { return }
        guard
            case .attaching(let priority, let attempt) = member.execution,
            attempt == admission.attempt,
            admission.generation == cohort.generation
        else {
            return
        }

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
        membersByPaneID[admission.descriptor.paneID] = member
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
