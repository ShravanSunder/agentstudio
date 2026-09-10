import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal

/// R4 remediation (PR #330): `acceptTerminalGeometry` and
/// `notifyWaitingForGeometryPlaceholders` must guard each placeholder
/// publication with a fresh, same-generation `ViewRegistry` custody read
/// immediately before writing. Without that guard, a pane whose custody
/// already advanced past `waitingForGeometry` (mounted or failed by a
/// concurrent path this coordinator's own scheduler settlement did not yet
/// reflect) gets a stale placeholder overlaid on its live terminal view,
/// which nothing ever clears. Split from
/// `WorkspacePreparedContentMountCoordinatorTests` to keep that suite under
/// the file-length lint budget.
@MainActor
@Suite("Workspace prepared content mount coordinator stale custody placeholders")
struct StaleCustodyPlaceholderTests {
    @Test("a requeue publishes no placeholder for a pane already completed")
    func aRequeuePublishesNoPlaceholderForAPaneAlreadyCompleted() async throws {
        // Arrange: `waiting` never becomes geometry-eligible at the
        // scheduler, so `mount()` settles it as `waitingForGeometry` there.
        // Its `ViewRegistry` custody is independently driven straight to
        // `completed`, standing in for a concurrent path (e.g. a real
        // reveal) that already mounted it before this requeue resumes.
        let generation = try makeStaleCustodyTestGeneration()
        let waiting = makeStaleCustodyTestDescriptor()
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(entries: [waiting]),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let terminalPort = RecordingStaleCustodyTerminalPort(descriptors: [waiting])
        let placeholderHandler = RecordingStaleCustodyPlaceholderTransitionHandler()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: registry,
            terminalAdmissionPort: terminalPort,
            nonterminalAdmissionPort: RecordingStaleCustodyNonterminalPort(),
            placeholderTransitionHandler: { pane, mode in placeholderHandler.handle(pane: pane, mode: mode) }
        )
        _ = await coordinator.mount()
        #expect(
            registry.claimPreparedContentMount(paneID: waiting.paneID, owner: .terminal, generation: generation)
                == .accepted
        )
        registry.settlePreparedContentMount(
            paneID: waiting.paneID,
            owner: .terminal,
            generation: generation,
            disposition: .mounted
        )

        // Act: the requeue still accepts `waiting` at the (independent, fake)
        // scheduler level, but live custody now says it already completed.
        await coordinator.acceptTerminalGeometry([waiting.paneID])

        // Assert: no `.preparing` placeholder was ever requested for it.
        #expect(placeholderHandler.requestedModesByPaneID[waiting.pane.id] == nil)
    }

    @Test("a frozen waitingForGeometry settlement publishes no placeholder for a pane already completed")
    func aFrozenWaitingForGeometrySettlementPublishesNoPlaceholderForAPaneAlreadyCompleted() async throws {
        // Arrange: drive `waiting`'s `ViewRegistry` custody to `completed`
        // BEFORE `mount()` runs. The scheduler still settles it as
        // `waitingForGeometry` in the frozen settlement (it never became
        // geometry-eligible), reproducing a settlement that is already
        // stale relative to live custody by the time the notify loop reads it.
        let generation = try makeStaleCustodyTestGeneration()
        let waiting = makeStaleCustodyTestDescriptor()
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(entries: [waiting]),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let terminalPort = RecordingStaleCustodyTerminalPort(descriptors: [waiting])
        let placeholderHandler = RecordingStaleCustodyPlaceholderTransitionHandler()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: registry,
            terminalAdmissionPort: terminalPort,
            nonterminalAdmissionPort: RecordingStaleCustodyNonterminalPort(),
            placeholderTransitionHandler: { pane, mode in placeholderHandler.handle(pane: pane, mode: mode) }
        )
        #expect(
            registry.claimPreparedContentMount(paneID: waiting.paneID, owner: .terminal, generation: generation)
                == .accepted
        )
        registry.settlePreparedContentMount(
            paneID: waiting.paneID,
            owner: .terminal,
            generation: generation,
            disposition: .mounted
        )

        // Act
        let settlement = await coordinator.mount()

        // Assert: the frozen settlement still reports waitingForGeometry
        // (the independent fake scheduler never learned about the custody
        // change), but no placeholder was published for it.
        #expect(settlement.terminal.outcomesByPaneID[waiting.paneID] == .waitingForGeometry)
        #expect(placeholderHandler.requestedModesByPaneID[waiting.pane.id] == nil)
    }
}

@MainActor
private final class RecordingStaleCustodyTerminalPort: TerminalActivationAdmissionPort {
    private let descriptorsByPaneID: [PaneId: TerminalActivationDescriptor]
    private(set) var recordedVisibleQueuedTerminals: [TerminalVisibleQueuedTerminals] = []

    init(descriptors: [TerminalActivationDescriptor] = []) {
        descriptorsByPaneID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.paneID, $0) })
    }

    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        recordedVisibleQueuedTerminals.append(terminals)
        return TerminalVisibilityRevision(
            generation: terminals.generation,
            ordinal: UInt64(recordedVisibleQueuedTerminals.count)
        )
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        guard let descriptor = descriptorsByPaneID[proposal.paneID] else {
            return .rejected(.paneNotInCohort)
        }
        return .claimed(
            ClaimedTerminalAdmission(
                claimID: UUIDv7.generate(),
                admission: TerminalActivationAdmission(
                    generation: proposal.generation,
                    descriptor: descriptor,
                    attempt: proposal.attempt
                ),
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision
            )
        )
    }

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        .attempted(.failed(failure: .attachmentRejected(code: "unexpected"), retry: .doNotRetry))
    }
}

@MainActor
private final class RecordingStaleCustodyNonterminalPort: NonterminalContentMountAdmissionPort {
    private(set) var descriptors: [NonterminalContentMountDescriptor] = []

    func mount(_ descriptor: NonterminalContentMountDescriptor) -> NonterminalContentMountAdmissionResult {
        descriptors.append(descriptor)
        return .mounted
    }
}

/// Mirrors `RecordingPlaceholderTransitionHandler` in
/// `WorkspacePreparedContentMountCoordinatorTests`: a recording-only stand-in
/// good enough to assert "no publication happened" without needing a real
/// `TerminalStatusPlaceholderView` host.
@MainActor
private final class RecordingStaleCustodyPlaceholderTransitionHandler {
    private(set) var requestedModesByPaneID: [UUID: [TerminalStatusPlaceholderMode]] = [:]

    func handle(pane: Pane, mode: TerminalStatusPlaceholderMode) {
        requestedModesByPaneID[pane.id, default: []].append(mode)
    }
}

@MainActor
private func makeStaleCustodyTestGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func makeStaleCustodyTestDescriptor(
    title: String = "Stale Custody Test Terminal"
) -> TerminalActivationDescriptor {
    let launchDirectory = URL(filePath: "/tmp/prepared-content-coordinator-stale-custody")
    let terminalState = TerminalState(
        provider: .zmx,
        lifetime: .persistent,
        zmxSessionID: .generateUUIDv7()
    )
    let pane = Pane(
        id: UUIDv7.generate(),
        content: .terminal(terminalState),
        metadata: PaneMetadata(
            launchDirectory: launchDirectory,
            title: title
        )
    )
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: .activeVisible,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}
