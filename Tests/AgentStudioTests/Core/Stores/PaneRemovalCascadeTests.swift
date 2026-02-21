import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PaneRemovalCascadeTests {

    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - Helpers

    private func createTabWithPanes(_ count: Int) -> (Tab, [UUID]) {
        let first = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: first.id)
        store.appendTab(tab)

        var paneIds = [first.id]
        for _ in 1..<count {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.insertPane(
                pane.id, inTab: tab.id, at: paneIds.last!,
                direction: .horizontal, position: .after
            )
            paneIds.append(pane.id)
        }
        return (store.tab(tab.id)!, paneIds)
    }

    // MARK: - removePane cascades to ALL arrangements

    @Test

    func test_removePane_removesFromDefaultAndCustomArrangements() {
        let (tab, paneIds) = createTabWithPanes(3)

        // Create a custom arrangement containing panes 0 and 1
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )!

        // Remove pane[1] globally
        store.removePane(paneIds[1])

        // Pane[1] should be gone from the store
        #expect((store.pane(paneIds[1])) == nil)

        // Should be removed from default arrangement
        let updatedTab = store.tabs.first { $0.id == tab.id }!
        let defaultArr = updatedTab.defaultArrangement
        #expect(!(defaultArr.layout.contains(paneIds[1])))
        #expect(!(defaultArr.visiblePaneIds.contains(paneIds[1])))

        // Should be removed from custom arrangement
        let customArr = updatedTab.arrangements.first { $0.id == arrId }!
        #expect(!(customArr.layout.contains(paneIds[1])))
        #expect(!(customArr.visiblePaneIds.contains(paneIds[1])))
    }

    @Test

    func test_removePane_resetsActivePaneId_ifRemoved() {
        let (tab, paneIds) = createTabWithPanes(3)
        store.setActivePane(paneIds[1], inTab: tab.id)
        #expect(store.tab(tab.id)!.activePaneId == paneIds[1])

        store.removePane(paneIds[1])

        let updatedTab = store.tabs.first { $0.id == tab.id }!
        #expect((updatedTab.activePaneId) != nil)
        #expect(updatedTab.activePaneId != paneIds[1])
    }

    @Test

    func test_removePane_clearsZoom_ifZoomedPaneRemoved() {
        let (tab, paneIds) = createTabWithPanes(2)
        store.toggleZoom(paneId: paneIds[0], inTab: tab.id)
        #expect(store.tab(tab.id)!.zoomedPaneId == paneIds[0])

        store.removePane(paneIds[0])

        let updatedTab = store.tabs.first { $0.id == tab.id }
        // Either tab removed (last pane in default) or zoom cleared
        if let tab = updatedTab {
            #expect((tab.zoomedPaneId) == nil)
        }
    }

    @Test

    func test_removePane_removesTabWhenDefaultArrangementEmpty() {
        let (tab, paneIds) = createTabWithPanes(1)

        store.removePane(paneIds[0])

        // Tab should be removed when its default arrangement becomes empty
        #expect(!store.tabs.contains(where: { $0.id == tab.id }))
    }

    @Test

    func test_removePane_removesFromTabPanesList() {
        let (tab, paneIds) = createTabWithPanes(3)

        store.removePane(paneIds[1])

        let updatedTab = store.tabs.first { $0.id == tab.id }!
        #expect(!(updatedTab.panes.contains(paneIds[1])))
        #expect(updatedTab.panes.count == 2)
    }

    // MARK: - removePaneFromLayout cascades across arrangements

    @Test

    func test_removePaneFromLayout_removesFromActiveAndDefault() {
        let (tab, paneIds) = createTabWithPanes(3)

        // Create and switch to custom arrangement
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )!
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Remove pane[1] from layout (while in custom arrangement)
        let isEmpty = store.removePaneFromLayout(paneIds[1], inTab: tab.id)

        #expect(!(isEmpty))

        let updatedTab = store.tab(tab.id)!

        // Removed from custom (active) arrangement
        let customArr = updatedTab.arrangements.first { $0.id == arrId }!
        #expect(!(customArr.layout.contains(paneIds[1])))

        // Also removed from default arrangement
        let defaultArr = updatedTab.defaultArrangement
        #expect(!(defaultArr.layout.contains(paneIds[1])))
    }

    @Test

    func test_removePaneFromLayout_resetsActivePaneId() {
        let (tab, paneIds) = createTabWithPanes(2)
        store.setActivePane(paneIds[1], inTab: tab.id)

        store.removePaneFromLayout(paneIds[1], inTab: tab.id)

        let updatedTab = store.tab(tab.id)
        // Either tab is empty or active pane was reset
        if let tab = updatedTab {
            #expect(tab.activePaneId != paneIds[1])
        }
    }

    @Test

    func test_removePaneFromLayout_clearsZoom() {
        let (tab, paneIds) = createTabWithPanes(3)
        store.toggleZoom(paneId: paneIds[1], inTab: tab.id)

        store.removePaneFromLayout(paneIds[1], inTab: tab.id)

        let updatedTab = store.tab(tab.id)!
        #expect((updatedTab.zoomedPaneId) == nil)
    }

    @Test

    func test_removePaneFromLayout_returnsTrue_whenLastPaneRemoved() {
        let (tab, paneIds) = createTabWithPanes(1)

        let isEmpty = store.removePaneFromLayout(paneIds[0], inTab: tab.id)

        #expect(isEmpty)
    }

    @Test

    func test_removePaneFromLayout_removesFromTabPanesList() {
        let (tab, paneIds) = createTabWithPanes(3)

        store.removePaneFromLayout(paneIds[1], inTab: tab.id)

        let updatedTab = store.tab(tab.id)!
        #expect(!(updatedTab.panes.contains(paneIds[1])))
    }

    // MARK: - Pane removal + drawer interaction

    @Test

    func test_removePane_withDrawer_removesEverything() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Add a drawer pane
        _ = store.addDrawerPane(to: pane.id)

        // Extra pane so tab doesn't get removed
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.insertPane(pane2.id, inTab: tab.id, at: pane.id, direction: .horizontal, position: .after)

        // Remove the pane that has a drawer
        store.removePane(pane.id)

        #expect((store.pane(pane.id)) == nil)
    }

    // MARK: - Orphan pool + removal interaction

    @Test

    func test_backgroundedPane_notInTabLayouts_removedByPurge() {
        let (tab, paneIds) = createTabWithPanes(2)
        let targetPaneId = paneIds[1]

        // Background the pane (removes from layout, keeps in store)
        store.backgroundPane(targetPaneId)

        // Pane should still exist in store but backgrounded
        #expect((store.pane(targetPaneId)) != nil)
        #expect(store.pane(targetPaneId)!.residency == .backgrounded)

        // Should not be in tab's active layout
        let updatedTab = store.tab(tab.id)!
        #expect(!(updatedTab.paneIds.contains(targetPaneId)))

        // Purge should remove it
        store.purgeOrphanedPane(targetPaneId)
        #expect((store.pane(targetPaneId)) == nil)
    }

    @Test

    func test_reactivatePane_restoresIntoLayout() {
        let (tab, paneIds) = createTabWithPanes(2)
        let targetPaneId = paneIds[1]

        store.backgroundPane(targetPaneId)
        #expect(!(store.tab(tab.id)!.paneIds.contains(targetPaneId)))

        // Reactivate by inserting next to the remaining pane
        store.reactivatePane(
            targetPaneId, inTab: tab.id,
            at: paneIds[0], direction: .horizontal, position: .after
        )

        #expect(store.tab(tab.id)!.paneIds.contains(targetPaneId))
        #expect(store.pane(targetPaneId)!.residency == .active)
    }

    // MARK: - Multiple tabs interaction

    @Test

    func test_removePane_cleanedFromMultipleTabs() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane3 = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        let tab1 = Tab(paneId: pane1.id)
        store.appendTab(tab1)
        store.insertPane(pane2.id, inTab: tab1.id, at: pane1.id, direction: .horizontal, position: .after)

        let tab2 = Tab(paneId: pane3.id)
        store.appendTab(tab2)
        store.insertPane(pane2.id, inTab: tab2.id, at: pane3.id, direction: .horizontal, position: .after)

        // Remove pane2 globally — should be removed from both tabs
        store.removePane(pane2.id)

        let updatedTab1 = store.tabs.first { $0.id == tab1.id }!
        let updatedTab2 = store.tabs.first { $0.id == tab2.id }!
        #expect(!(updatedTab1.paneIds.contains(pane2.id)))
        #expect(!(updatedTab2.paneIds.contains(pane2.id)))
    }
}
