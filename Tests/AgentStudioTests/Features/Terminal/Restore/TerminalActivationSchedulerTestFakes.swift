import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

/// Shared by the scheduler-correctness fakes below. `claimPreparedTerminal`
/// needs the descriptor for a proposed `paneID` to mint a `ClaimedTerminalAdmission`;
/// these fakes carry no `ViewRegistry` of their own, so the test constructing
/// the scheduler's cohort also registers that cohort's descriptors here.
@MainActor
protocol FakeTerminalActivationAdmissionPort: TerminalActivationAdmissionPort {
    var descriptorsByPaneID: [PaneId: TerminalActivationDescriptor] { get set }
}

@MainActor
final class ImmediateTerminalActivationAdmissionPort: FakeTerminalActivationAdmissionPort {
    private var resultsByPaneID: [PaneId: [TerminalActivationAttemptResult]]
    var descriptorsByPaneID: [PaneId: TerminalActivationDescriptor] = [:]
    private(set) var admissions: [TerminalActivationAdmission] = []

    init(resultsByPaneID: [PaneId: [TerminalActivationAttemptResult]] = [:]) {
        self.resultsByPaneID = resultsByPaneID
    }

    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        TerminalVisibilityRevision(generation: terminals.generation, ordinal: 0)
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        guard let descriptor = descriptorsByPaneID[proposal.paneID] else {
            return .rejected(.paneNotInCohort)
        }
        let admission = TerminalActivationAdmission(
            generation: proposal.generation,
            descriptor: descriptor,
            attempt: proposal.attempt
        )
        return .claimed(
            ClaimedTerminalAdmission(
                claimID: UUIDv7.generate(),
                admission: admission,
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision
            )
        )
    }

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        let admission = claim.admission
        admissions.append(admission)
        if var results = resultsByPaneID[admission.descriptor.paneID], !results.isEmpty {
            let result = results.removeFirst()
            resultsByPaneID[admission.descriptor.paneID] = results
            return .attempted(result)
        }
        return .attempted(.ready(surfaceID: UUIDv7.generate()))
    }
}

/// Always rejects every claim proposal, for proving the scheduler never marks
/// a member `attaching` before a claim is granted.
@MainActor
final class RejectingTerminalActivationAdmissionPort: FakeTerminalActivationAdmissionPort {
    var descriptorsByPaneID: [PaneId: TerminalActivationDescriptor] = [:]
    private(set) var claimProposals: [TerminalAdmissionProposal] = []

    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        TerminalVisibilityRevision(generation: terminals.generation, ordinal: 0)
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        claimProposals.append(proposal)
        return .rejected(.custodyUnavailableForClaim)
    }

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        .rejected(.claimNotIssued)
    }
}

@MainActor
final class ControlledTerminalActivationAdmissionPort: FakeTerminalActivationAdmissionPort {
    private struct PendingAdmission {
        let admission: TerminalActivationAdmission
        let continuation: CheckedContinuation<TerminalActivationAttemptResult, Never>
    }

    var descriptorsByPaneID: [PaneId: TerminalActivationDescriptor] = [:]
    private var pending: [PendingAdmission] = []
    private var startedCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var admissions: [TerminalActivationAdmission] = []

    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        TerminalVisibilityRevision(generation: terminals.generation, ordinal: 0)
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        guard let descriptor = descriptorsByPaneID[proposal.paneID] else {
            return .rejected(.paneNotInCohort)
        }
        let admission = TerminalActivationAdmission(
            generation: proposal.generation,
            descriptor: descriptor,
            attempt: proposal.attempt
        )
        return .claimed(
            ClaimedTerminalAdmission(
                claimID: UUIDv7.generate(),
                admission: admission,
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision
            )
        )
    }

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        let admission = claim.admission
        admissions.append(admission)
        resumeSatisfiedStartedCountWaiters()
        let result = await withCheckedContinuation { continuation in
            pending.append(PendingAdmission(admission: admission, continuation: continuation))
        }
        return .attempted(result)
    }

    func waitUntilStartedCount(_ count: Int) async {
        guard admissions.count < count else { return }
        await withCheckedContinuation { continuation in
            startedCountWaiters.append((count, continuation))
        }
    }

    @discardableResult
    func releaseFirstPendingAsReady() -> TerminalActivationAdmission? {
        guard !pending.isEmpty else {
            Issue.record("Expected a pending terminal activation admission")
            return nil
        }
        let pendingAdmission = pending.removeFirst()
        pendingAdmission.continuation.resume(returning: .ready(surfaceID: UUIDv7.generate()))
        return pendingAdmission.admission
    }

    func releaseAllPendingAsReady() {
        let pendingAdmissions = pending
        pending.removeAll()
        for pendingAdmission in pendingAdmissions {
            pendingAdmission.continuation.resume(returning: .ready(surfaceID: UUIDv7.generate()))
        }
    }

    private func resumeSatisfiedStartedCountWaiters() {
        let ready = startedCountWaiters.filter { $0.0 <= admissions.count }
        startedCountWaiters.removeAll { $0.0 <= admissions.count }
        for waiter in ready { waiter.1.resume() }
    }
}

/// A more faithful fake than `ImmediateTerminalActivationAdmissionPort`:
/// tracks a real revision-bearing snapshot and rejects a proposal whose
/// applied revision is stale, exactly like the production port's G1/G6
/// behavior. The promotion tests need this: they must observe the
/// scheduler's real response to a `.visibilityChanged` outcome, not a
/// synchronous rubber stamp that always claims.
@MainActor
final class RevisionAwareTerminalActivationAdmissionPort: TerminalActivationAdmissionPort {
    private struct PendingActivation {
        let admission: TerminalActivationAdmission
        let continuation: CheckedContinuation<TerminalActivationAttemptResult, Never>
    }

    private let descriptorsByPaneID: [PaneId: TerminalActivationDescriptor]
    private var currentSnapshot: TerminalVisibleQueuedSnapshot
    private var resultsByPaneID: [PaneId: [TerminalActivationAttemptResult]]
    private let suspendsActivation: Bool
    private var pending: [PendingActivation] = []
    private var startedCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var admissions: [TerminalActivationAdmission] = []
    private(set) var claimProposals: [TerminalAdmissionProposal] = []

    init(
        generation: WorkspaceContentMountGeneration,
        descriptors: [TerminalActivationDescriptor],
        resultsByPaneID: [PaneId: [TerminalActivationAttemptResult]] = [:],
        suspendsActivation: Bool = false
    ) {
        descriptorsByPaneID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.paneID, $0) })
        currentSnapshot = TerminalVisibleQueuedSnapshot(
            revision: TerminalVisibilityRevision(generation: generation, ordinal: 0),
            terminals: TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [],
                visibleMainSiblingPaneIDs: [],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )
        self.resultsByPaneID = resultsByPaneID
        self.suspendsActivation = suspendsActivation
    }

    @discardableResult
    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        guard terminals != currentSnapshot.terminals else { return currentSnapshot.revision }
        let nextRevision = TerminalVisibilityRevision(
            generation: currentSnapshot.revision.generation,
            ordinal: currentSnapshot.revision.ordinal + 1
        )
        currentSnapshot = TerminalVisibleQueuedSnapshot(revision: nextRevision, terminals: terminals)
        return nextRevision
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        claimProposals.append(proposal)
        guard let descriptor = descriptorsByPaneID[proposal.paneID] else {
            return .rejected(.paneNotInCohort)
        }
        guard proposal.appliedVisibilityRevision == currentSnapshot.revision else {
            return .visibilityChanged(currentSnapshot)
        }
        let admission = TerminalActivationAdmission(
            generation: proposal.generation,
            descriptor: descriptor,
            attempt: proposal.attempt
        )
        return .claimed(
            ClaimedTerminalAdmission(
                claimID: UUIDv7.generate(),
                admission: admission,
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision
            )
        )
    }

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        let admission = claim.admission
        admissions.append(admission)
        resumeSatisfiedStartedCountWaiters()
        if suspendsActivation {
            let result = await withCheckedContinuation { continuation in
                pending.append(PendingActivation(admission: admission, continuation: continuation))
            }
            return .attempted(result)
        }
        if var results = resultsByPaneID[admission.descriptor.paneID], !results.isEmpty {
            let result = results.removeFirst()
            resultsByPaneID[admission.descriptor.paneID] = results
            return .attempted(result)
        }
        return .attempted(.ready(surfaceID: UUIDv7.generate()))
    }

    func waitUntilStartedCount(_ count: Int) async {
        guard admissions.count < count else { return }
        await withCheckedContinuation { continuation in
            startedCountWaiters.append((count, continuation))
        }
    }

    @discardableResult
    func releaseFirstPendingAsReady() -> TerminalActivationAdmission? {
        releaseFirstPending(with: .ready(surfaceID: UUIDv7.generate()))
    }

    @discardableResult
    func releaseFirstPending(with result: TerminalActivationAttemptResult) -> TerminalActivationAdmission? {
        guard !pending.isEmpty else {
            Issue.record("Expected a pending terminal activation admission")
            return nil
        }
        let pendingActivation = pending.removeFirst()
        pendingActivation.continuation.resume(returning: result)
        return pendingActivation.admission
    }

    func releaseAllPendingAsReady() {
        let pendingActivations = pending
        pending.removeAll()
        for pendingActivation in pendingActivations {
            pendingActivation.continuation.resume(returning: .ready(surfaceID: UUIDv7.generate()))
        }
    }

    private func resumeSatisfiedStartedCountWaiters() {
        let ready = startedCountWaiters.filter { $0.0 <= admissions.count }
        startedCountWaiters.removeAll { $0.0 <= admissions.count }
        for waiter in ready { waiter.1.resume() }
    }
}

/// Lets exactly one `activateClaimedTerminal` call reenter the scheduler via
/// `acceptLaterGeometry` before returning its own result — simulating S9's
/// geometry-reevaluation tail landing during the final activation of
/// `activate()`'s own drain, the exact interleaving S10b's settlement-race
/// fix must survive. `scheduler` is assigned after construction because the
/// port must exist before the scheduler that owns it.
@MainActor
final class ReentrantAcceptGeometryAdmissionPort: FakeTerminalActivationAdmissionPort {
    var descriptorsByPaneID: [PaneId: TerminalActivationDescriptor] = [:]
    weak var scheduler: TerminalActivationScheduler?
    /// The pane whose claim triggers the reentrant `acceptLaterGeometry`
    /// call, and the still-`waitingForGeometry` pane that call names.
    var reentryTriggerPaneID: PaneId?
    var lateArrivingPaneID: PaneId?
    private(set) var admissions: [TerminalActivationAdmission] = []
    private(set) var acceptedLateArrivals: Set<PaneId> = []
    private var hasTriggeredReentry = false

    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        TerminalVisibilityRevision(generation: terminals.generation, ordinal: 0)
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        guard let descriptor = descriptorsByPaneID[proposal.paneID] else {
            return .rejected(.paneNotInCohort)
        }
        let admission = TerminalActivationAdmission(
            generation: proposal.generation,
            descriptor: descriptor,
            attempt: proposal.attempt
        )
        return .claimed(
            ClaimedTerminalAdmission(
                claimID: UUIDv7.generate(),
                admission: admission,
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision
            )
        )
    }

    /// Resolved once the spawned reentrant call has recorded its result, so
    /// a caller can `await` that fact deterministically instead of polling
    /// or sleeping. Replaced with a fresh continuation by
    /// `armReentryCompletionWaiter()` before each `activate()` call that
    /// needs to observe it.
    private var reentryContinuation: CheckedContinuation<Void, Never>?

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        let admission = claim.admission
        admissions.append(admission)
        if !hasTriggeredReentry, admission.descriptor.paneID == reentryTriggerPaneID,
            let lateArrivingPaneID, let scheduler
        {
            hasTriggeredReentry = true
            // Spawned, not awaited: this lets `runWorker()`'s own resumption
            // (hopping back to the scheduler actor the instant this MainActor
            // call returns) race ahead of this call's own hop through the
            // cooperative thread pool into `acceptLaterGeometry` — landing it
            // after the worker's last `nextQueuedCandidate()` check, in the
            // window `activate()`'s settlement-race fix must survive. A
            // direct `await` here is absorbed by this same worker's very next
            // loop iteration instead (verified empirically: it never
            // reproduces the race), which is why S10b's fix could not be
            // proven with the naive direct-await shape.
            Task { [weak self] in
                guard let self else { return }
                let accepted = await scheduler.acceptLaterGeometry(for: [lateArrivingPaneID])
                await self.recordAcceptedLateArrivals(accepted)
            }
        }
        return .attempted(.ready(surfaceID: UUIDv7.generate()))
    }

    private func recordAcceptedLateArrivals(_ accepted: Set<PaneId>) {
        acceptedLateArrivals = accepted
        reentryContinuation?.resume()
        reentryContinuation = nil
    }

    /// Bounded wait for the spawned reentrant call to actually complete, so a
    /// test that needs to confirm the reentry landed (rather than merely
    /// racing it against `activate()`) can do so deterministically. Returns
    /// immediately if it has already landed.
    func waitUntilReentryLands() async {
        guard acceptedLateArrivals.isEmpty else { return }
        await withCheckedContinuation { continuation in
            reentryContinuation = continuation
        }
    }
}

actor TerminalActivationCompletionProbe {
    private(set) var settlement: TerminalActivationSettlement?

    var isCompleted: Bool { settlement != nil }

    func record(_ settlement: TerminalActivationSettlement) {
        self.settlement = settlement
    }
}

actor ControlledTerminalActivationReleaseSignal: TerminalActivationReleaseSignal {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var waitStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private var isSchedulerWaiting = false
    private var isReleased = false

    func waitUntilReleased() async -> StartupDeferralOutcome {
        guard !isReleased else { return .completed }
        isSchedulerWaiting = true
        let startedContinuations = waitStartedContinuations
        waitStartedContinuations.removeAll()
        for continuation in startedContinuations {
            continuation.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return .completed
    }

    func waitUntilSchedulerIsWaiting() async {
        guard !isSchedulerWaiting else { return }
        await withCheckedContinuation { continuation in
            waitStartedContinuations.append(continuation)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}
