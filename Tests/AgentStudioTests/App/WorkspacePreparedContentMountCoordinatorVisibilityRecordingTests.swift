import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal

/// R2 remediation (PR #330): `handleVisibilitySignals` must forward every
/// observation to the terminal admission port, including one whose queued
/// terminal subset is empty, so a previously promoted member can be demoted.
/// Split from `WorkspacePreparedContentMountCoordinatorTests` to keep that
/// suite under the file-length lint budget.
@MainActor
@Suite("Workspace prepared content mount coordinator visibility recording")
struct PreparedContentVisibilityRecordingTests {
    @Test("an observation with no queued terminals is still recorded, not discarded")
    func anObservationWithNoQueuedTerminalsIsStillRecordedNotDiscarded() throws {
        // Arrange: a queued drawer pane is promoted into the current visible
        // queued set by a first, nonempty observation.
        let generation = try makeVisibilityRecordingTestGeneration()
        let tabID = UUIDv7.generate()
        let parentPaneID = PaneId(existingUUID: UUIDv7.generate())
        let drawerID = UUIDv7.generate()
        let drawerTerminal = makeVisibilityRecordingTestTerminalDescriptor(
            title: "Queued drawer terminal",
            visibilityPriority: .hidden,
            hostPlacement: .drawer(tabID: tabID, parentPaneID: parentPaneID, drawerID: drawerID)
        )
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(entries: [drawerTerminal]),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let terminalPort = RecordingVisibilityRecordingTerminalPort(descriptors: [drawerTerminal])
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: registry,
            terminalAdmissionPort: terminalPort,
            nonterminalAdmissionPort: RecordingVisibilityRecordingNonterminalPort()
        )
        _ = coordinator.handleVisibilitySignals(
            for: PreparedContentVisibleQueuedSet(
                visiblePaneIDs: [drawerTerminal.paneID],
                activePaneIDs: [drawerTerminal.paneID]
            )
        )

        // Act: nothing is visible any more, so the classified queued-terminal
        // subset is empty. The coordinator must still forward this
        // observation instead of discarding it.
        let handledPaneIDs = coordinator.handleVisibilitySignals(
            for: PreparedContentVisibleQueuedSet(visiblePaneIDs: [], activePaneIDs: [])
        )

        // Assert
        #expect(handledPaneIDs.isEmpty)
        #expect(terminalPort.recordedVisibleQueuedTerminals.count == 2)
        #expect(
            terminalPort.recordedVisibleQueuedTerminals.last
                == TerminalVisibleQueuedTerminals(
                    generation: generation,
                    activeMainPaneIDs: [],
                    visibleMainSiblingPaneIDs: [],
                    activeDrawerPaneIDs: [],
                    visibleDrawerSiblingPaneIDs: []
                )
        )
    }
}

/// Mirrors `RecordingPreparedContentTerminalPort` in
/// `WorkspacePreparedContentMountCoordinatorTests`: carries no `ViewRegistry`
/// of its own, so the caller registers the cohort's descriptors at
/// construction.
@MainActor
private final class RecordingVisibilityRecordingTerminalPort: TerminalActivationAdmissionPort {
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
private final class RecordingVisibilityRecordingNonterminalPort: NonterminalContentMountAdmissionPort {
    private(set) var descriptors: [NonterminalContentMountDescriptor] = []

    func mount(_ descriptor: NonterminalContentMountDescriptor) -> NonterminalContentMountAdmissionResult {
        descriptors.append(descriptor)
        return .mounted
    }
}

@MainActor
private func makeVisibilityRecordingTestGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func makeVisibilityRecordingTestTerminalDescriptor(
    title: String = "Prepared Coordinator Terminal",
    visibilityPriority: TerminalActivationVisibilityPriority = .activeVisible,
    hostPlacement: TerminalHostPlacementIdentity = .tab(tabID: UUIDv7.generate())
) -> TerminalActivationDescriptor {
    let launchDirectory = URL(filePath: "/tmp/prepared-content-coordinator-visibility-recording")
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
        visibilityPriority: visibilityPriority,
        hostPlacement: hostPlacement
    )
}
