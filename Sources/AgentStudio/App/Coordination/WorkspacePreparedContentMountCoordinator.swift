import Foundation

struct WorkspacePreparedContentMountSettlement: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let terminal: TerminalActivationSettlement
    let nonterminal: NonterminalContentMountSettlement
}

/// Joins the independently scheduled terminal and nonterminal startup lanes for
/// one accepted composition generation.
@MainActor
final class WorkspacePreparedContentMountCoordinator {
    private enum Lifecycle {
        case idle
        case mounting
        case settled(WorkspacePreparedContentMountSettlement)
    }

    private let cohort: WorkspacePreparedContentMountCohort
    private let viewRegistry: ViewRegistry
    private let terminalScheduler: TerminalActivationScheduler
    private let nonterminalOwner: NonterminalContentMountOwner
    private var lifecycle = Lifecycle.idle
    private var waiters: [CheckedContinuation<WorkspacePreparedContentMountSettlement, Never>] = []
    private var deferredVisibilityIntentPaneIDs: Set<PaneId> = []
    private var deferredVisibilityIntentOrder: [PaneId] = []

    init(
        cohort: WorkspacePreparedContentMountCohort,
        viewRegistry: ViewRegistry,
        terminalAdmissionPort: any TerminalActivationAdmissionPort,
        nonterminalAdmissionPort: any NonterminalContentMountAdmissionPort
    ) {
        // Hidden Bridge panes stay outside the startup ledger so a later reveal
        // falls through to the existing steady-state content mount owner.
        let startupCohort = WorkspacePreparedContentMountCohort(
            generation: cohort.generation,
            terminalActivationInput: cohort.terminalActivationInput,
            nonterminalContentMountInput: NonterminalContentMountInput(
                entries: cohort.nonterminalContentMountInput.entries.filter {
                    guard $0.visibilityPriority == .hidden else { return true }
                    guard case .bridgePanel = $0.content else { return true }
                    return false
                }
            )
        )
        self.cohort = startupCohort
        self.viewRegistry = viewRegistry
        terminalScheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: startupCohort.generation,
                input: startupCohort.terminalActivationInput
            ),
            admissionPort: terminalAdmissionPort
        )
        nonterminalOwner = NonterminalContentMountOwner(
            generation: startupCohort.generation,
            input: startupCohort.nonterminalContentMountInput,
            admissionPort: nonterminalAdmissionPort
        )
        viewRegistry.installPreparedContentMountCohort(startupCohort)
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

        async let terminal = terminalScheduler.activate()
        async let nonterminal = nonterminalOwner.mount()
        let settlement = WorkspacePreparedContentMountSettlement(
            generation: cohort.generation,
            terminal: await terminal,
            nonterminal: await nonterminal
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
            case .pending(owner: .terminal):
                handledPaneIDs.insert(paneID)
                recordDeferredVisibilityIntent(for: paneID)
                terminalPaneIDsToPromote.append(paneID)
            case .mounting(owner: .terminal), .pending(owner: .nonterminal), .mounting(owner: .nonterminal):
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
            Task { [terminalScheduler] in
                for paneID in terminalPaneIDsToPromote {
                    _ = await terminalScheduler.promote(paneID: paneID, to: .activeVisible)
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
}
