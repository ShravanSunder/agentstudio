import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import Foundation

struct WorkspacePreparedContentMountSettlement: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let terminal: TerminalActivationSettlement
    let nonterminal: NonterminalContentMountSettlement
}

struct TerminalPlaceholderPublication: Equatable, Sendable {
    enum Disposition: Equatable, Sendable {
        case published
        case joinedExistingPublication
    }

    let paneIDs: [PaneId]
    let disposition: Disposition
}

/// Joins the single-scheduler terminal lane and the phase-ordered nonterminal
/// startup lane for one accepted composition generation.
@MainActor
final class WorkspacePreparedContentMountCoordinator {
    private enum Lifecycle {
        case idle
        case mounting
        case settled(WorkspacePreparedContentMountSettlement)
    }

    private let cohort: WorkspacePreparedContentMountCohort
    private let viewRegistry: ViewRegistry
    private let terminalActivationReleaseGate: TerminalActivationReleaseGate
    /// One scheduler owns the complete terminal cohort — foreground and
    /// hidden, main and drawer alike. Its private `QueueRank` reproduces the
    /// former four-phase admission order without four scheduler instances, so
    /// the whole-cohort concurrency bound (R4) can no longer be exceeded by
    /// summing several schedulers' individual bounds.
    private let terminalScheduler: TerminalActivationScheduler
    /// Nonterminal startup keeps its existing two-phase order (main before
    /// drawer) and ledger semantics, unchanged by this slice. Hidden
    /// nonterminal panes are excluded before this array is built.
    private let nonterminalPhaseOwners: [NonterminalContentMountOwner]
    private var lifecycle = Lifecycle.idle
    private var didPublishTerminalPlaceholders = false
    private var waiters: [CheckedContinuation<WorkspacePreparedContentMountSettlement, Never>] = []
    private var deferredVisibilityIntentPaneIDs: Set<PaneId> = []
    private var deferredVisibilityIntentOrder: [PaneId] = []

    init(
        cohort: WorkspacePreparedContentMountCohort,
        viewRegistry: ViewRegistry,
        terminalAdmissionPort: any TerminalActivationAdmissionPort,
        nonterminalAdmissionPort: any NonterminalContentMountAdmissionPort
    ) {
        // Hidden nonterminal panes stay outside the startup ledger so later
        // demand falls through to the existing steady-state content mount
        // owner. Terminals remain in the startup cohort — foreground and
        // hidden alike — and the scheduler's own rank orders them.
        let startupCohort = WorkspacePreparedContentMountCohort(
            generation: cohort.generation,
            terminalActivationInput: cohort.terminalActivationInput,
            nonterminalContentMountInput: NonterminalContentMountInput(
                entries: cohort.nonterminalContentMountInput.entries.filter { $0.visibilityPriority != .hidden }
            )
        )
        self.cohort = startupCohort
        self.viewRegistry = viewRegistry
        let terminalActivationReleaseGate = TerminalActivationReleaseGate(isReleased: true)
        self.terminalActivationReleaseGate = terminalActivationReleaseGate
        terminalScheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: startupCohort.generation,
                input: startupCohort.terminalActivationInput
            ),
            admissionPort: terminalAdmissionPort,
            releaseSignal: terminalActivationReleaseGate
        )
        nonterminalPhaseOwners = [false, true].map { selectingDrawerEntries in
            NonterminalContentMountOwner(
                generation: startupCohort.generation,
                input: NonterminalContentMountInput(
                    entries: startupCohort.nonterminalContentMountInput.entries.filter {
                        Self.isDrawerPlacement($0.hostPlacement) == selectingDrawerEntries
                    }
                ),
                admissionPort: nonterminalAdmissionPort
            )
        }
        viewRegistry.installPreparedContentMountCohort(startupCohort)
    }

    func holdTerminalActivationUntilReleased() async {
        await terminalActivationReleaseGate.hold()
    }

    func releaseTerminalActivation() async {
        await terminalActivationReleaseGate.release()
    }

    func terminalActivationDeferralOutcome() async -> StartupDeferralOutcome? {
        await terminalScheduler.recordedActivationDeferralOutcome()
    }

    func mount() async -> WorkspacePreparedContentMountSettlement {
        switch lifecycle {
        case .settled(let settlement):
            return settlement
        case .mounting:
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        case .idle:
            lifecycle = .mounting
        }

        async let terminalSettlement = terminalScheduler.activate()

        var nonterminalOutcomesByPaneID: [PaneId: NonterminalContentMountOutcome] = [:]
        for nonterminalOwner in nonterminalPhaseOwners {
            let phaseNonterminal = await nonterminalOwner.mount()
            nonterminalOutcomesByPaneID.merge(phaseNonterminal.outcomesByPaneID) { _, _ in
                preconditionFailure("nonterminal pane admitted by multiple restore phases")
            }
        }

        let settlement = WorkspacePreparedContentMountSettlement(
            generation: cohort.generation,
            terminal: await terminalSettlement,
            nonterminal: NonterminalContentMountSettlement(
                generation: cohort.generation,
                outcomesByPaneID: nonterminalOutcomesByPaneID
            )
        )
        requireCompleteSettlement(settlement)
        viewRegistry.completeInitialRestore()
        lifecycle = .settled(settlement)

        let completedWaiters = waiters
        waiters.removeAll()
        for waiter in completedWaiters {
            waiter.resume(returning: settlement)
        }
        return settlement
    }

    /// Publishes the accepted restore cohort in stable order without starting
    /// terminal activation. The caller owns the concrete placeholder host.
    func publishTerminalPlaceholders(
        using publish: (TerminalActivationDescriptor) -> Void
    ) -> TerminalPlaceholderPublication {
        let descriptors = cohort.terminalActivationInput.entries
        guard !didPublishTerminalPlaceholders else {
            return TerminalPlaceholderPublication(
                paneIDs: descriptors.map(\.paneID),
                disposition: .joinedExistingPublication
            )
        }
        precondition(
            {
                if case .idle = lifecycle { return true }
                return false
            }(),
            "terminal placeholders must publish before prepared content mounting"
        )
        didPublishTerminalPlaceholders = true
        for descriptor in descriptors {
            publish(descriptor)
        }
        return TerminalPlaceholderPublication(
            paneIDs: descriptors.map(\.paneID),
            disposition: .published
        )
    }

    func promoteTerminal(
        paneID: PaneId,
        to priority: TerminalActivationVisibilityPriority
    ) async -> TerminalActivationPromotionResult {
        await terminalScheduler.promote(paneID: paneID, to: priority)
    }

    func handleVisibilitySignals(for paneIDs: [PaneId]) -> Set<PaneId> {
        var handledPaneIDs: Set<PaneId> = []
        var terminalPaneIDsToPromote: [PaneId] = []
        for paneID in paneIDs {
            guard
                let state = viewRegistry.preparedContentMountState(
                    for: paneID,
                    generation: cohort.generation
                )
            else {
                continue
            }
            switch state {
            case .pending(owner: .terminal), .deferredGeometry(owner: .terminal):
                // A pane waiting on geometry is treated exactly like a pending
                // pane here: the prepared lane still owns it, and this signal
                // only records intent and (harmlessly) promotes its priority
                // for whenever it becomes claimable again.
                handledPaneIDs.insert(paneID)
                recordDeferredVisibilityIntent(for: paneID)
                terminalPaneIDsToPromote.append(paneID)
            case .mounting(owner: .terminal), .pending(owner: .nonterminal), .mounting(owner: .nonterminal),
                .deferredGeometry(owner: .nonterminal):
                handledPaneIDs.insert(paneID)
                recordDeferredVisibilityIntent(for: paneID)
            case .completed(owner: _, disposition: .failed):
                handledPaneIDs.insert(paneID)
                recordDeferredVisibilityIntent(for: paneID)
            case .completed:
                handledPaneIDs.insert(paneID)
            }
        }
        if !terminalPaneIDsToPromote.isEmpty {
            let terminalScheduler = terminalScheduler
            Task {
                for paneID in terminalPaneIDsToPromote {
                    _ = await terminalScheduler.promote(
                        paneID: paneID,
                        to: .activeVisible
                    )
                }
            }
        }
        return handledPaneIDs
    }

    func takeDeferredSteadyStateRepairPaneIDs() -> [PaneId] {
        guard case .settled(let settlement) = lifecycle else {
            preconditionFailure("deferred steady-state repair read before aggregate settlement")
        }
        let failedPaneIDs = failedPaneIDs(in: settlement)
        let deferredPaneIDs = deferredVisibilityIntentOrder.filter { paneID in
            guard deferredVisibilityIntentPaneIDs.contains(paneID) else { return false }
            return failedPaneIDs.contains(paneID)
        }
        deferredVisibilityIntentPaneIDs.removeAll()
        deferredVisibilityIntentOrder.removeAll()
        return deferredPaneIDs
    }

    private func failedPaneIDs(
        in settlement: WorkspacePreparedContentMountSettlement
    ) -> Set<PaneId> {
        let failedTerminalPaneIDs = settlement.terminal.outcomesByPaneID.compactMap { paneID, outcome in
            switch outcome {
            case .failedTerminal:
                return paneID
            case .ready, .cancelledReplaced:
                return nil
            }
        }
        let failedNonterminalPaneIDs = settlement.nonterminal.outcomesByPaneID.compactMap { paneID, outcome in
            switch outcome {
            case .failedNonterminal:
                return paneID
            case .mounted, .cancelledReplaced:
                return nil
            }
        }
        return Set(failedTerminalPaneIDs).union(failedNonterminalPaneIDs)
    }

    private func recordDeferredVisibilityIntent(for paneID: PaneId) {
        guard deferredVisibilityIntentPaneIDs.insert(paneID).inserted else { return }
        deferredVisibilityIntentOrder.append(paneID)
    }

    private func requireCompleteSettlement(_ settlement: WorkspacePreparedContentMountSettlement) {
        precondition(settlement.terminal.generation == cohort.generation)
        precondition(settlement.nonterminal.generation == cohort.generation)
        precondition(
            Set(settlement.terminal.outcomesByPaneID.keys)
                == Set(cohort.terminalActivationInput.entries.map(\.paneID))
        )
        precondition(
            Set(settlement.nonterminal.outcomesByPaneID.keys)
                == Set(cohort.nonterminalContentMountInput.entries.map(\.paneID))
        )
    }

    private static func isDrawerPlacement(_ placement: TerminalHostPlacementIdentity) -> Bool {
        if case .drawer = placement { return true }
        return false
    }
}
