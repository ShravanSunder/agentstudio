import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace preinstall zmx-anchor repair coordinator")
struct WorkspacePreinstallZmxAnchorRepairCoordinatorTests {
    @Test("mixed repair applies every accepted anchor in one revision")
    func mixedRepairAppliesAcceptedAnchorsInOneRevision() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        let changedPaneA = makePreinstallZmxPane()
        let changedPaneB = makePreinstallZmxPane()
        let unchangedPaneID = UUIDv7.generate()
        let unchangedSessionID = makePreinstallMainSessionID(
            paneID: unchangedPaneID,
            seed: "3"
        )
        let unchangedPane = makePreinstallZmxPane(
            paneID: unchangedPaneID,
            sessionID: unchangedSessionID
        )
        let ghosttyPane = makePreinstallGhosttyPane()
        for paneState in [changedPaneA, changedPaneB, unchangedPane, ghosttyPane] {
            atomRegistry.workspacePaneGraph.setCanonicalPaneState(paneState)
        }
        for _ in 0..<300 {
            atomRegistry.workspacePaneGraph.setCanonicalPaneState(makePreinstallZmxPane())
        }
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let sessionIDA = makePreinstallMainSessionID(paneID: changedPaneA.id, seed: "1")
        let sessionIDB = makePreinstallMainSessionID(paneID: changedPaneB.id, seed: "2")
        let missingPaneID = UUIDv7.generate()
        let diagnosticsBefore = runtime.adapters.workspacePaneGraph.participantDiagnostics()

        // Act
        let result = runtime.preinstallZmxAnchorRepairCoordinator.repair([
            .init(paneID: changedPaneA.id, sessionID: sessionIDA),
            .init(paneID: changedPaneB.id, sessionID: sessionIDB),
            .init(paneID: unchangedPane.id, sessionID: unchangedSessionID),
            .init(paneID: ghosttyPane.id, sessionID: "invalid-for-ghostty"),
            .init(paneID: missingPaneID, sessionID: "invalid-for-missing"),
        ])

        // Assert
        guard case .changed(let revision, let report) = result else {
            Issue.record("expected one changed preinstall repair")
            return
        }
        #expect(revision.rawValue == 1)
        #expect(runtime.revisionOwner.committedRevision == revision)
        #expect(report.acceptedPaneIDs == [changedPaneA.id, changedPaneB.id])
        #expect(report.unchangedPaneIDs == [unchangedPane.id])
        #expect(
            report.rejections
                == [
                    .init(
                        paneID: ghosttyPane.id,
                        reason: .providerMismatch(received: .ghostty)
                    ),
                    .init(paneID: missingPaneID, reason: .paneMissing),
                ]
        )
        #expect(preinstallZmxSessionID(in: atomRegistry.workspacePaneGraph.paneState(changedPaneA.id)) == sessionIDA)
        #expect(preinstallZmxSessionID(in: atomRegistry.workspacePaneGraph.paneState(changedPaneB.id)) == sessionIDB)
        let diagnosticsAfter = runtime.adapters.workspacePaneGraph.participantDiagnostics()
        #expect(
            diagnosticsAfter.persistenceCapturePaneLookupCount
                - diagnosticsBefore.persistenceCapturePaneLookupCount == 2
        )
    }

    @Test("all unchanged or rejected entries publish no revision")
    func unchangedRepairPublishesNoRevision() {
        // Arrange
        let atomRegistry = AtomRegistry()
        let paneID = UUIDv7.generate()
        let sessionID = makePreinstallMainSessionID(paneID: paneID, seed: "4")
        atomRegistry.workspacePaneGraph.setCanonicalPaneState(
            makePreinstallZmxPane(paneID: paneID, sessionID: sessionID)
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)

        // Act
        let result = runtime.preinstallZmxAnchorRepairCoordinator.repair([
            .init(paneID: paneID, sessionID: sessionID),
            .init(paneID: UUIDv7.generate(), sessionID: "missing"),
        ])

        // Assert
        guard case .unchanged(let revision, let report) = result else {
            Issue.record("expected unchanged preinstall repair")
            return
        }
        #expect(revision == .zero)
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(report.acceptedPaneIDs.isEmpty)
        #expect(report.unchangedPaneIDs == [paneID])
        #expect(report.rejections.count == 1)
        #expect(runtime.adapters.workspacePaneGraph.participantDiagnostics().persistenceCapturePaneLookupCount == 0)
    }

    @Test("reentrant revision custody rejects without applying anchors")
    func reentrantRevisionCustodyRejectsWithoutMutation() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        let pane = makePreinstallZmxPane()
        atomRegistry.workspacePaneGraph.setCanonicalPaneState(pane)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let sessionID = makePreinstallMainSessionID(paneID: pane.id, seed: "5")

        // Act
        let nestedResult = try runtime.revisionOwner.performSynchronousTransactionDecision { _ in
            .unchanged(
                runtime.preinstallZmxAnchorRepairCoordinator.repair([
                    .init(paneID: pane.id, sessionID: sessionID)
                ])
            )
        }

        // Assert
        #expect(nestedResult == .rejected(.revisionOwner(.reentrantTransaction)))
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(preinstallZmxSessionID(in: atomRegistry.workspacePaneGraph.paneState(pane.id)) == nil)
    }

    @Test("composition installation seals the preinstall repair route")
    func compositionInstallationSealsRepairRoute() {
        // Arrange
        let atomRegistry = AtomRegistry()
        let pane = makePreinstallZmxPane()
        atomRegistry.workspacePaneGraph.setCanonicalPaneState(pane)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let sessionID = makePreinstallMainSessionID(paneID: pane.id, seed: "6")
        _ = runtime.snapshotParticipantFactory.constructCompositionParticipantSet()

        // Act
        let result = runtime.preinstallZmxAnchorRepairCoordinator.repair([
            .init(paneID: pane.id, sessionID: sessionID)
        ])

        // Assert
        guard case .rejected(.lifecycle(.preinstallAccessUnavailable(let phase))) = result else {
            Issue.record("expected installed lifecycle rejection")
            return
        }
        guard case .installed = phase else {
            Issue.record("expected installed composition phase")
            return
        }
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(preinstallZmxSessionID(in: atomRegistry.workspacePaneGraph.paneState(pane.id)) == nil)
    }
}

private func makePreinstallZmxPane(
    paneID: UUID = UUIDv7.generate(),
    sessionID: String? = nil
) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: paneID,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionId: sessionID
                )
            ),
            metadata: PaneMetadata(title: "Zmx")
        )
    )
}

private func makePreinstallGhosttyPane() -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(provider: .ghostty, lifetime: .temporary)
            ),
            metadata: PaneMetadata(title: "Ghostty")
        )
    )
}

private func makePreinstallMainSessionID(paneID: UUID, seed: Character) -> String {
    let stableKey = String(repeating: seed, count: 16)
    return ZmxBackend.sessionId(
        repoStableKey: stableKey,
        worktreeStableKey: stableKey,
        paneId: paneID
    )
}

private func preinstallZmxSessionID(in paneState: PaneGraphState?) -> String? {
    guard let paneState, case .terminal(let terminalState) = paneState.content else { return nil }
    return terminalState.zmxSessionId
}
