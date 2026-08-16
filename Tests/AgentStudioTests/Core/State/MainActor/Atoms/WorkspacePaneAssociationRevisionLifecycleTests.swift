import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace pane association revision lifecycle")
struct WorkspacePaneAssociationRevisionLifecycleTests {
    @Test("Pane deletion discards association revision history before identifier reuse")
    func paneDeletionDiscardsAssociationRevisionHistory() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/revision-delete", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        _ = graphAtom.reservePaneAssociationRevision(pane.id)
        _ = graphAtom.reservePaneAssociationRevision(pane.id)
        let restoredPane = try #require(graphAtom.paneState(pane.id)?.pane(isDrawerExpanded: false))

        #expect(graphAtom.deletePaneAndOwnedDrawerChildren(pane.id))
        #expect(graphAtom.insertRestoredPane(restoredPane))

        let firstReusedRevision = try #require(graphAtom.reservePaneAssociationRevision(pane.id))
        #expect(firstReusedRevision.rawValue == 2)
    }

    @Test("Owned drawer deletion discards child association revision history")
    func ownedDrawerDeletionDiscardsChildAssociationRevisionHistory() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let parentPane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/revision-drawer", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let drawerPane = try #require(
            graphAtom.addDrawerPane(
                to: parentPane.id,
                content: .terminal(
                    TerminalState(
                        provider: .zmx,
                        lifetime: .persistent,
                        zmxSessionID: .generateUUIDv7()
                    )
                ),
                metadata: PaneMetadata(
                    launchDirectory: URL(filePath: "/tmp/revision-drawer", directoryHint: .isDirectory),
                    title: "Drawer"
                )
            )
        )
        _ = graphAtom.reservePaneAssociationRevision(drawerPane.id)
        _ = graphAtom.reservePaneAssociationRevision(drawerPane.id)
        let restoredDrawerPane = drawerPane.pane(isDrawerExpanded: false)

        #expect(graphAtom.deletePaneAndOwnedDrawerChildren(parentPane.id))
        graphAtom.addPane(restoredDrawerPane)

        let firstReusedRevision = try #require(
            graphAtom.reservePaneAssociationRevision(drawerPane.id)
        )
        #expect(firstReusedRevision.rawValue == 2)
    }

    @Test("Pane graph replacement resets association revisions to exact replacement membership")
    func paneGraphReplacementResetsAssociationRevisionMembership() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let removedPane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/revision-replaced", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        _ = graphAtom.reservePaneAssociationRevision(removedPane.id)
        _ = graphAtom.reservePaneAssociationRevision(removedPane.id)
        let replacementPane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/revision-replacement", directoryHint: .isDirectory),
                title: "Replacement"
            )
        )

        graphAtom.replacePaneStates(
            try requirePaneGraphReplacement([
                replacementPane.id: PaneGraphState(pane: replacementPane)
            ])
        )
        let replacementRevision = try #require(
            graphAtom.reservePaneAssociationRevision(replacementPane.id)
        )
        graphAtom.addPane(removedPane.pane(isDrawerExpanded: false))
        let reusedRemovedRevision = try #require(
            graphAtom.reservePaneAssociationRevision(removedPane.id)
        )

        #expect(replacementRevision.rawValue == 1)
        #expect(reusedRemovedRevision.rawValue == 2)
    }

    private func requirePaneGraphReplacement(
        _ paneStates: [UUID: PaneGraphState]
    ) throws -> WorkspacePaneGraphReplacement {
        switch WorkspacePaneGraphReplacement.prepare(paneStates) {
        case .success(let replacement):
            return replacement
        case .failure:
            throw WorkspacePaneAssociationRevisionLifecycleTestError.replacementRejected
        }
    }
}

private enum WorkspacePaneAssociationRevisionLifecycleTestError: Error {
    case replacementRejected
}
