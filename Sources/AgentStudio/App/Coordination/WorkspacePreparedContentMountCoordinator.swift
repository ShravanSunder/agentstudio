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

/// Joins the independently scheduled terminal and nonterminal startup lanes for
/// one accepted composition generation.
@MainActor
final class WorkspacePreparedContentMountCoordinator {
    private struct MountPhase {
        let terminalScheduler: TerminalActivationScheduler
        let nonterminalOwner: NonterminalContentMountOwner
    }

    private enum Lifecycle {
        case idle
        case mounting
        case settled(WorkspacePreparedContentMountSettlement)
    }

    private let cohort: WorkspacePreparedContentMountCohort
    private let viewRegistry: ViewRegistry
    private let terminalActivationReleaseGate: TerminalActivationReleaseGate
    private let phases: [MountPhase]
    private let terminalSchedulersByPaneID: [PaneId: TerminalActivationScheduler]
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
        // owner. Terminals remain in the startup cohort and restore after the
        // foreground phases.
        let startupCohort = WorkspacePreparedContentMountCohort(
            generation: cohort.generation,
            terminalActivationInput: cohort.terminalActivationInput,
            nonterminalContentMountInput: NonterminalContentMountInput(
                entries: cohort.nonterminalContentMountInput.entries.filter { $0.visibilityPriority != .hidden }
            )
        )
        let foregroundCohort = WorkspacePreparedContentMountCohort(
            generation: startupCohort.generation,
            terminalActivationInput: TerminalActivationInput(
                entries: startupCohort.terminalActivationInput.entries.filter {
                    $0.visibilityPriority != .hidden
                }
            ),
            nonterminalContentMountInput: startupCohort.nonterminalContentMountInput
        )
        let hiddenTerminalCohort = WorkspacePreparedContentMountCohort(
            generation: startupCohort.generation,
            terminalActivationInput: TerminalActivationInput(
                entries: startupCohort.terminalActivationInput.entries.filter {
                    $0.visibilityPriority == .hidden
                }
            ),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        self.cohort = startupCohort
        self.viewRegistry = viewRegistry
        let terminalActivationReleaseGate = TerminalActivationReleaseGate(isReleased: true)
        self.terminalActivationReleaseGate = terminalActivationReleaseGate
        let phaseCohorts = [
            Self.partition(foregroundCohort, selectingDrawerEntries: false),
            Self.partition(foregroundCohort, selectingDrawerEntries: true),
            Self.partition(hiddenTerminalCohort, selectingDrawerEntries: false),
            Self.partition(hiddenTerminalCohort, selectingDrawerEntries: true),
        ]
        let phases = phaseCohorts.map { phaseCohort in
            MountPhase(
                terminalScheduler: TerminalActivationScheduler(
                    cohort: TerminalActivationCohort(
                        generation: phaseCohort.generation,
                        input: phaseCohort.terminalActivationInput
                    ),
                    admissionPort: terminalAdmissionPort,
                    releaseSignal: terminalActivationReleaseGate
                ),
                nonterminalOwner: NonterminalContentMountOwner(
                    generation: phaseCohort.generation,
                    input: phaseCohort.nonterminalContentMountInput,
                    admissionPort: nonterminalAdmissionPort
                )
            )
        }
        self.phases = phases
        terminalSchedulersByPaneID = Dictionary(
            uniqueKeysWithValues: zip(phaseCohorts, phases).flatMap { phaseCohort, phase in
                phaseCohort.terminalActivationInput.entries.map {
                    ($0.paneID, phase.terminalScheduler)
                }
            }
        )
        viewRegistry.installPreparedContentMountCohort(startupCohort)
    }

    func holdTerminalActivationUntilReleased() async {
        await terminalActivationReleaseGate.hold()
    }

    func releaseTerminalActivation() async {
        await terminalActivationReleaseGate.release()
    }

    func terminalActivationDeferralOutcome() async -> StartupDeferralOutcome? {
        guard let firstPhase = phases.first else { return nil }
        return await firstPhase.terminalScheduler.recordedActivationDeferralOutcome()
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

        var terminalOutcomesByPaneID: [PaneId: TerminalActivationTerminalOutcome] = [:]
        var nonterminalOutcomesByPaneID: [PaneId: NonterminalContentMountOutcome] = [:]
        for phase in phases {
            async let terminal = phase.terminalScheduler.activate()
            async let nonterminal = phase.nonterminalOwner.mount()
            let phaseTerminal = await terminal
            let phaseNonterminal = await nonterminal
            terminalOutcomesByPaneID.merge(phaseTerminal.outcomesByPaneID) { _, _ in
                preconditionFailure("terminal pane admitted by multiple restore phases")
            }
            nonterminalOutcomesByPaneID.merge(phaseNonterminal.outcomesByPaneID) { _, _ in
                preconditionFailure("nonterminal pane admitted by multiple restore phases")
            }
        }
        let settlement = WorkspacePreparedContentMountSettlement(
            generation: cohort.generation,
            terminal: TerminalActivationSettlement(
                generation: cohort.generation,
                outcomesByPaneID: terminalOutcomesByPaneID
            ),
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
        guard let terminalScheduler = terminalSchedulersByPaneID[paneID] else {
            return .paneNotFound
        }
        return await terminalScheduler.promote(paneID: paneID, to: priority)
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
            let terminalSchedulersByPaneID = terminalSchedulersByPaneID
            Task {
                for paneID in terminalPaneIDsToPromote {
                    _ = await terminalSchedulersByPaneID[paneID]?.promote(
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

    private static func partition(
        _ cohort: WorkspacePreparedContentMountCohort,
        selectingDrawerEntries: Bool
    ) -> WorkspacePreparedContentMountCohort {
        WorkspacePreparedContentMountCohort(
            generation: cohort.generation,
            terminalActivationInput: TerminalActivationInput(
                entries: cohort.terminalActivationInput.entries.filter {
                    isDrawerPlacement($0.hostPlacement) == selectingDrawerEntries
                }
            ),
            nonterminalContentMountInput: NonterminalContentMountInput(
                entries: cohort.nonterminalContentMountInput.entries.filter {
                    isDrawerPlacement($0.hostPlacement) == selectingDrawerEntries
                }
            )
        )
    }

    private static func isDrawerPlacement(_ placement: TerminalHostPlacementIdentity) -> Bool {
        if case .drawer = placement { return true }
        return false
    }
}
