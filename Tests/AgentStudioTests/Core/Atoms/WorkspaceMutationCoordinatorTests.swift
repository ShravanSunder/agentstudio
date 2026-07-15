import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceMutationCoordinatorTests {
    @Test
    func reactivatePane_failedInsert_keepsPaneBackgrounded() {
        let topologyAtom = RepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabShellAtom = WorkspaceTabShellAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom()
        let coordinator = WorkspaceMutationCoordinator(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
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
        let topologyAtom = RepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabShellAtom = WorkspaceTabShellAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom()
        let coordinator = WorkspaceMutationCoordinator(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
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
        let topologyAtom = RepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabShellAtom = WorkspaceTabShellAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom()
        let coordinator = WorkspaceMutationCoordinator(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabShellAtom: tabShellAtom,
            workspaceTabArrangementAtom: tabArrangementAtom
        )

        let parentPaneId = UUID()
        let drawerPane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Drawer"),
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
    func restoreDrawerPane_forcesDetachedPaneBackToDrawerChildKind() throws {
        let paneAtom = WorkspacePaneAtom()
        let parentPane = makePane(title: "Parent")
        paneAtom.addPane(parentPane)
        let drawerPane = try #require(
            paneAtom.addDrawerPane(
                to: parentPane.id,
                parentFallbackCWD: nil
            )
        )

        let detachedPane = try #require(paneAtom.detachDrawerPane(drawerPane.id, from: parentPane.id))
        guard case .layout(let detachedDrawer) = detachedPane.kind else {
            Issue.record("Expected detached drawer pane to become a layout pane")
            return
        }
        #expect(detachedDrawer.parentPaneId == drawerPane.id)

        #expect(paneAtom.restoreDrawerPane(detachedPane, to: parentPane.id))

        let restoredPane = try #require(paneAtom.pane(drawerPane.id))
        #expect(restoredPane.kind == .drawerChild(parentPaneId: parentPane.id))
        #expect(paneAtom.pane(parentPane.id)?.drawer?.paneIds == [drawerPane.id])
    }

    @Test
    func restoreFromPaneSnapshot_parentPaneRestoresDrawerViewsAndTabMembership() throws {
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
        )
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

    @Test
    func snapshotForClose_withDrawerChildrenCapturesEachPaneExactlyOnce() throws {
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
        )
        let parentPane = makePane(title: "Parent")
        store.paneAtom.addPane(parentPane)
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

        let snapshot = try #require(store.mutationCoordinator.snapshotForClose(tabId: tab.id))

        let snapshottedPaneIds = snapshot.panes.map(\.id)
        #expect(
            snapshottedPaneIds == [
                parentPane.id,
                firstDrawerPane.id,
                secondDrawerPane.id,
            ]
        )
        #expect(Set(snapshottedPaneIds).count == snapshottedPaneIds.count)
    }

    @Test
    func backgroundPane_removesOwnedDrawerViewsFromVisibleTab() throws {
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
        )
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
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)

        #expect(store.mutationCoordinator.backgroundPane(parentPane.id))

        let restoredTab = try #require(store.tab(tab.id))
        #expect(restoredTab.allPaneIds == [anchorPane.id])
        #expect(restoredTab.arrangements.allSatisfy { $0.drawerViews[drawerId] == nil })
        #expect(store.pane(parentPane.id)?.residency == .backgrounded)
        #expect(store.pane(drawerPane.id)?.residency == .backgrounded)
        #expect(store.pane(drawerPane.id)?.kind == .drawerChild(parentPaneId: parentPane.id))
        #expect(store.orphanedPanes.map(\.id) == [parentPane.id])
    }

    @Test
    func backgroundPane_reactivatePane_restoresOwnedDrawerViewsAndChildMembership() throws {
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
        )
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
        let tabBeforeBackground = try #require(store.tab(tab.id))
        let drawerViewsBeforeBackground = Dictionary(
            uniqueKeysWithValues: tabBeforeBackground.arrangements.compactMap { arrangement in
                arrangement.drawerViews[drawerId].map { (arrangement.id, $0) }
            }
        )

        #expect(store.mutationCoordinator.backgroundPane(parentPane.id))
        #expect(
            store.mutationCoordinator.reactivatePane(
                parentPane.id,
                inTab: tab.id,
                at: anchorPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )

        let restoredTab = try #require(store.tab(tab.id))
        #expect(restoredTab.allPaneIds.contains(parentPane.id))
        #expect(restoredTab.allPaneIds.contains(firstDrawerPane.id))
        #expect(restoredTab.allPaneIds.contains(secondDrawerPane.id))
        #expect(store.pane(parentPane.id)?.residency == .active)
        #expect(store.pane(firstDrawerPane.id)?.residency == .active)
        #expect(store.pane(secondDrawerPane.id)?.residency == .active)
        #expect(
            Dictionary(
                uniqueKeysWithValues: restoredTab.arrangements.compactMap { arrangement in
                    arrangement.drawerViews[drawerId].map { (arrangement.id, $0) }
                }
            ) == drawerViewsBeforeBackground
        )
    }
}
