import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceMutationCoordinatorTests {
    @Test
    func reactivatePane_failedInsert_keepsPaneBackgrounded() {
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        let coordinator = WorkspaceMutationCoordinator(
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        let pane = makePane(residency: .backgrounded)
        paneAtom.addPane(pane)

        let didReactivate = coordinator.reactivatePane(
            pane.id,
            inTab: UUID(),
            at: UUID(),
            direction: .horizontal,
            position: .after
        )

        #expect(!didReactivate)
        #expect(paneAtom.pane(pane.id)?.residency == .backgrounded)
        #expect(!tabLayoutAtom.allPaneIds.contains(pane.id))
    }

    @Test
    func restoreFromPaneSnapshot_failedLayoutInsertion_cleansUpRestoredPaneState() {
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        let coordinator = WorkspaceMutationCoordinator(
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        let pane = makePane()
        let snapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot(
            pane: pane,
            drawerChildPanes: [],
            tabId: UUID(),
            anchorPaneId: UUID(),
            direction: .horizontal
        )

        let result = coordinator.restoreFromPaneSnapshot(snapshot)

        #expect(
            result
                == .failedLayoutInsertion(
                    tabId: snapshot.tabId,
                    anchorPaneId: snapshot.anchorPaneId
                )
        )
        #expect(paneAtom.pane(pane.id) == nil)
    }

    @Test
    func restoreFromPaneSnapshot_failedDrawerParent_cleansUpRestoredDrawerPaneState() {
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        let coordinator = WorkspaceMutationCoordinator(
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        let parentPaneId = UUID()
        let drawerPane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: nil), title: "Drawer"),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
        let snapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot(
            pane: drawerPane,
            drawerChildPanes: [],
            tabId: UUID(),
            anchorPaneId: parentPaneId,
            direction: .horizontal
        )

        let result = coordinator.restoreFromPaneSnapshot(snapshot)

        #expect(result == .failedMissingDrawerParent(parentPaneId))
        #expect(paneAtom.pane(drawerPane.id) == nil)
    }
}
