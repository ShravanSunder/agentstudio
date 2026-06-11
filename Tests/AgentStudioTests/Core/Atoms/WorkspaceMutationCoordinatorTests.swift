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
        let tabShellAtom = WorkspaceTabShellAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom()
        let coordinator = WorkspaceMutationCoordinator(
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabShellAtom: tabShellAtom,
            workspaceTabArrangementAtom: tabArrangementAtom
        )

        let pane = makePane(residency: .backgrounded)
        paneAtom.addPane(pane)

        let didReactivate = coordinator.reactivatePane(
            pane.id,
            inTab: UUID(),
            at: UUID(),
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        #expect(!didReactivate)
        #expect(paneAtom.pane(pane.id)?.residency == .backgrounded)
        #expect(!tabArrangementAtom.allPaneIds.contains(pane.id))
    }

    @Test
    func restoreFromPaneSnapshot_failedLayoutInsertion_cleansUpRestoredPaneState() {
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabShellAtom = WorkspaceTabShellAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom()
        let coordinator = WorkspaceMutationCoordinator(
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabShellAtom: tabShellAtom,
            workspaceTabArrangementAtom: tabArrangementAtom
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
        let tabShellAtom = WorkspaceTabShellAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom()
        let coordinator = WorkspaceMutationCoordinator(
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabShellAtom: tabShellAtom,
            workspaceTabArrangementAtom: tabArrangementAtom
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

    @Test
    func restoreFromPaneSnapshot_parentPaneRestoresDrawerViewsAndTabMembership() throws {
        let store = WorkspaceStore()
        let anchorPane = makePane(title: "Anchor")
        let parentPane = makePane(title: "Parent")
        store.paneAtom.addPane(anchorPane)
        store.paneAtom.addPane(parentPane)

        let tab = Tab(paneId: anchorPane.id)
        store.appendTab(tab)
        #expect(
            store.insertPane(
                parentPane.id,
                inTab: tab.id,
                at: anchorPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        store.setActiveDrawerPane(secondDrawerPane.id, in: parentPane.id)
        let focusArrangementId = try #require(store.createArrangement(name: "Drawer focus", inTab: tab.id))
        store.switchArrangement(to: focusArrangementId, inTab: tab.id)

        let snapshot = try #require(store.snapshotForPaneClose(paneId: parentPane.id, inTab: tab.id))
        let tabBeforeClose = try #require(store.tab(tab.id))
        let drawerViewsBeforeClose = tabBeforeClose.arrangements.compactMap {
            $0.drawerViews[drawerId]
        }

        #expect(store.mutationCoordinator.removePane(parentPane.id))
        let restoreResult = store.mutationCoordinator.restoreFromPaneSnapshot(snapshot)

        let restoredTab = try #require(store.tab(tab.id))
        #expect(restoreResult == .restored)
        #expect(restoredTab.allPaneIds.contains(parentPane.id))
        #expect(restoredTab.allPaneIds.contains(firstDrawerPane.id))
        #expect(restoredTab.allPaneIds.contains(secondDrawerPane.id))
        #expect(
            restoredTab.arrangements.compactMap { $0.drawerViews[drawerId] }
                == drawerViewsBeforeClose
        )
    }
}
