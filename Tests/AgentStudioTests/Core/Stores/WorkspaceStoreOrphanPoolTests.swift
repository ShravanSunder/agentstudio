import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreOrphanPoolTests {

    private var store: WorkspaceStore!

        init() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - Helpers

    private func createTabWithPane() -> (Tab, Pane) {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        return (tab, pane)
    }

    // MARK: - orphanedPanes query

    @Test

    func test_orphanedPanes_emptyByDefault() {
        _ = createTabWithPane()

        #expect(store.orphanedPanes.isEmpty)
    }

    @Test

    func test_orphanedPanes_returnsBackgroundedPanes() {
        let (_, pane1) = createTabWithPane()
        let (_, pane2) = createTabWithPane()

        store.backgroundPane(pane1.id)

        #expect(store.orphanedPanes.count == 1)
        #expect(store.orphanedPanes[0].id == pane1.id)

        // pane2 is still active
        #expect(!(store.orphanedPanes.contains { $0.id == pane2.id }))
    }

    // MARK: - backgroundPane

    @Test

    func test_backgroundPane_removesFromLayout() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after)

        store.backgroundPane(pane1.id)

        // Pane1 should be gone from layout
        let updatedTab = store.tab(tab.id)!
        #expect(!(updatedTab.panes.contains(pane1.id)))
        #expect(updatedTab.panes.contains(pane2.id))

        // But still in the store dict
        #expect((store.pane(pane1.id)) != nil)
        #expect(store.pane(pane1.id)!.residency == .backgrounded)
    }

    @Test

    func test_backgroundPane_lastPaneRemovesTab() {
        let (tab, pane) = createTabWithPane()

        store.backgroundPane(pane.id)

        #expect((store.tab(tab.id)) == nil)
        #expect((store.pane(pane.id)) != nil)
        #expect(store.pane(pane.id)!.residency == .backgrounded)
    }

    @Test

    func test_backgroundPane_updatesActivePaneId() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after)
        store.setActivePane(pane1.id, inTab: tab.id)

        store.backgroundPane(pane1.id)

        // Active pane should update to remaining pane
        #expect(store.tab(tab.id)!.activePaneId == pane2.id)
    }

    @Test

    func test_backgroundPane_clearsZoomIfZoomed() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after)
        store.toggleZoom(paneId: pane1.id, inTab: tab.id)

        store.backgroundPane(pane1.id)

        #expect((store.tab(tab.id)!.zoomedPaneId) == nil)
    }

    @Test

    func test_backgroundPane_marksDirty() {
        let (_, pane) = createTabWithPane()
        store.flush()

        store.backgroundPane(pane.id)

        #expect(store.isDirty)
    }

    // MARK: - reactivatePane

    @Test

    func test_reactivatePane_insertsIntoLayout() {
        let (tab1, pane1) = createTabWithPane()
        let (_, pane2) = createTabWithPane()

        store.backgroundPane(pane2.id)
        #expect(store.orphanedPanes.count == 1)

        store.reactivatePane(
            pane2.id, inTab: tab1.id, at: pane1.id,
            direction: .horizontal, position: .after
        )

        // Should now be in tab1's layout
        let updatedTab = store.tab(tab1.id)!
        #expect(updatedTab.panes.contains(pane2.id))
        #expect(store.pane(pane2.id)!.residency == .active)
        #expect(store.orphanedPanes.isEmpty)
    }

    @Test

    func test_reactivatePane_nonBackgrounded_noOp() {
        let (tab, pane1) = createTabWithPane()
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after)

        // pane2 is active, not backgrounded
        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after
        )

        // Should remain as-is (no duplicate insertion)
        #expect(store.pane(pane2.id)!.residency == .active)
    }

    // MARK: - purgeOrphanedPane

    @Test

    func test_purgeOrphanedPane_removesFromStore() {
        let (_, pane) = createTabWithPane()
        store.backgroundPane(pane.id)
        #expect((store.pane(pane.id)) != nil)

        store.purgeOrphanedPane(pane.id)

        #expect((store.pane(pane.id)) == nil)
        #expect(store.orphanedPanes.isEmpty)
    }

    @Test

    func test_purgeOrphanedPane_activePane_noOp() {
        let (_, pane) = createTabWithPane()

        store.purgeOrphanedPane(pane.id)

        // Should NOT remove an active pane
        #expect((store.pane(pane.id)) != nil)
    }

    // MARK: - Full lifecycle

    @Test

    func test_fullLifecycle_background_reactivate() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after)

        // Background pane2
        store.backgroundPane(pane2.id)
        #expect(store.orphanedPanes.count == 1)
        #expect(store.tab(tab.id)!.panes == [pane1.id])

        // Reactivate pane2 back into the same tab
        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after
        )
        #expect(store.orphanedPanes.isEmpty)
        #expect(store.tab(tab.id)!.panes.contains(pane2.id))
        #expect(store.pane(pane2.id)!.residency == .active)
    }

    @Test

    func test_fullLifecycle_background_purge() {
        let (_, pane) = createTabWithPane()

        store.backgroundPane(pane.id)
        #expect((store.pane(pane.id)) != nil)

        store.purgeOrphanedPane(pane.id)
        #expect((store.pane(pane.id)) == nil)
    }
}
