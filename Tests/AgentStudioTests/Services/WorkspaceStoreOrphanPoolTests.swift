import XCTest
@testable import AgentStudio

@MainActor
final class WorkspaceStoreOrphanPoolTests: XCTestCase {

    private var store: WorkspaceStore!

    override func setUp() {
        super.setUp()
        store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - Helpers

    private func createTabWithPane() -> (Tab, Pane) {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        return (tab, pane)
    }

    // MARK: - orphanedPanes query

    func test_orphanedPanes_emptyByDefault() {
        _ = createTabWithPane()

        XCTAssertTrue(store.orphanedPanes.isEmpty)
    }

    func test_orphanedPanes_returnsBackgroundedPanes() {
        let (_, pane1) = createTabWithPane()
        let (_, pane2) = createTabWithPane()

        store.backgroundPane(pane1.id)

        XCTAssertEqual(store.orphanedPanes.count, 1)
        XCTAssertEqual(store.orphanedPanes[0].id, pane1.id)

        // pane2 is still active
        XCTAssertFalse(store.orphanedPanes.contains { $0.id == pane2.id })
    }

    // MARK: - backgroundPane

    func test_backgroundPane_removesFromLayout() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(pane2.id, inTab: tab.id, at: pane1.id,
                         direction: .horizontal, position: .after)

        store.backgroundPane(pane1.id)

        // Pane1 should be gone from layout
        let updatedTab = store.tab(tab.id)!
        XCTAssertFalse(updatedTab.panes.contains(pane1.id))
        XCTAssertTrue(updatedTab.panes.contains(pane2.id))

        // But still in the store dict
        XCTAssertNotNil(store.pane(pane1.id))
        XCTAssertEqual(store.pane(pane1.id)!.residency, .backgrounded)
    }

    func test_backgroundPane_lastPaneRemovesTab() {
        let (tab, pane) = createTabWithPane()

        store.backgroundPane(pane.id)

        XCTAssertNil(store.tab(tab.id))
        XCTAssertNotNil(store.pane(pane.id))
        XCTAssertEqual(store.pane(pane.id)!.residency, .backgrounded)
    }

    func test_backgroundPane_updatesActivePaneId() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(pane2.id, inTab: tab.id, at: pane1.id,
                         direction: .horizontal, position: .after)
        store.setActivePane(pane1.id, inTab: tab.id)

        store.backgroundPane(pane1.id)

        // Active pane should update to remaining pane
        XCTAssertEqual(store.tab(tab.id)!.activePaneId, pane2.id)
    }

    func test_backgroundPane_clearsZoomIfZoomed() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(pane2.id, inTab: tab.id, at: pane1.id,
                         direction: .horizontal, position: .after)
        store.toggleZoom(paneId: pane1.id, inTab: tab.id)

        store.backgroundPane(pane1.id)

        XCTAssertNil(store.tab(tab.id)!.zoomedPaneId)
    }

    func test_backgroundPane_marksDirty() {
        let (_, pane) = createTabWithPane()
        store.flush()

        store.backgroundPane(pane.id)

        XCTAssertTrue(store.isDirty)
    }

    // MARK: - reactivatePane

    func test_reactivatePane_insertsIntoLayout() {
        let (tab1, pane1) = createTabWithPane()
        let (_, pane2) = createTabWithPane()

        store.backgroundPane(pane2.id)
        XCTAssertEqual(store.orphanedPanes.count, 1)

        store.reactivatePane(
            pane2.id, inTab: tab1.id, at: pane1.id,
            direction: .horizontal, position: .after
        )

        // Should now be in tab1's layout
        let updatedTab = store.tab(tab1.id)!
        XCTAssertTrue(updatedTab.panes.contains(pane2.id))
        XCTAssertEqual(store.pane(pane2.id)!.residency, .active)
        XCTAssertTrue(store.orphanedPanes.isEmpty)
    }

    func test_reactivatePane_nonBackgrounded_noOp() {
        let (tab, pane1) = createTabWithPane()
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.insertPane(pane2.id, inTab: tab.id, at: pane1.id,
                         direction: .horizontal, position: .after)

        // pane2 is active, not backgrounded
        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after
        )

        // Should remain as-is (no duplicate insertion)
        XCTAssertEqual(store.pane(pane2.id)!.residency, .active)
    }

    // MARK: - purgeOrphanedPane

    func test_purgeOrphanedPane_removesFromStore() {
        let (_, pane) = createTabWithPane()
        store.backgroundPane(pane.id)
        XCTAssertNotNil(store.pane(pane.id))

        store.purgeOrphanedPane(pane.id)

        XCTAssertNil(store.pane(pane.id))
        XCTAssertTrue(store.orphanedPanes.isEmpty)
    }

    func test_purgeOrphanedPane_activePane_noOp() {
        let (_, pane) = createTabWithPane()

        store.purgeOrphanedPane(pane.id)

        // Should NOT remove an active pane
        XCTAssertNotNil(store.pane(pane.id))
    }

    // MARK: - Full lifecycle

    func test_fullLifecycle_background_reactivate() {
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(pane2.id, inTab: tab.id, at: pane1.id,
                         direction: .horizontal, position: .after)

        // Background pane2
        store.backgroundPane(pane2.id)
        XCTAssertEqual(store.orphanedPanes.count, 1)
        XCTAssertEqual(store.tab(tab.id)!.panes, [pane1.id])

        // Reactivate pane2 back into the same tab
        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after
        )
        XCTAssertTrue(store.orphanedPanes.isEmpty)
        XCTAssertTrue(store.tab(tab.id)!.panes.contains(pane2.id))
        XCTAssertEqual(store.pane(pane2.id)!.residency, .active)
    }

    func test_fullLifecycle_background_purge() {
        let (_, pane) = createTabWithPane()

        store.backgroundPane(pane.id)
        XCTAssertNotNil(store.pane(pane.id))

        store.purgeOrphanedPane(pane.id)
        XCTAssertNil(store.pane(pane.id))
    }
}
