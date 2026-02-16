import XCTest
@testable import AgentStudio

@MainActor
final class WorkspaceStoreDrawerTests: XCTestCase {

    private var store: WorkspaceStore!

    override func setUp() {
        super.setUp()
        store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - addDrawerPane

    func test_addDrawerPane_createsDrawerChild() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Act
        let dp = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer Terminal")
        )

        // Assert
        XCTAssertNotNil(dp)
        let updated = store.pane(pane.id)!
        XCTAssertNotNil(updated.drawer)
        XCTAssertEqual(updated.drawer!.paneIds.count, 1)
        XCTAssertEqual(updated.drawer!.paneIds[0], dp!.id)
        XCTAssertEqual(updated.drawer!.activePaneId, dp!.id)
        XCTAssertTrue(updated.drawer!.isExpanded)

        // Drawer pane is a real entry in store.panes
        let drawerPaneInStore = store.pane(dp!.id)
        XCTAssertNotNil(drawerPaneInStore)
        XCTAssertTrue(drawerPaneInStore!.isDrawerChild)
        XCTAssertEqual(drawerPaneInStore!.parentPaneId, pane.id)
    }

    func test_addDrawerPane_appendsToExistingDrawer() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "First")
        )!

        let dp2 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Second")
        )!

        let updated = store.pane(pane.id)!
        XCTAssertEqual(updated.drawer!.paneIds.count, 2)
        XCTAssertEqual(updated.drawer!.activePaneId, dp2.id) // last added becomes active
        XCTAssertEqual(updated.drawer!.paneIds[1], dp2.id)

        // Both drawer panes are in the layout
        XCTAssertTrue(updated.drawer!.layout.contains(dp1.id))
        XCTAssertTrue(updated.drawer!.layout.contains(dp2.id))
    }

    func test_addDrawerPane_invalidParent_returnsNil() {
        let dp = store.addDrawerPane(
            to: UUID(),
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )

        XCTAssertNil(dp)
    }

    func test_addDrawerPane_marksDirty() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.flush()

        _ = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )

        XCTAssertTrue(store.isDirty)
    }

    // MARK: - removeDrawerPane

    func test_removeDrawerPane_removesFromDrawer() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "First")
        )!
        let dp2 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Second")
        )!

        store.removeDrawerPane(dp1.id, from: pane.id)

        let updated = store.pane(pane.id)!
        XCTAssertEqual(updated.drawer!.paneIds.count, 1)
        XCTAssertEqual(updated.drawer!.paneIds[0], dp2.id)

        // dp1 removed from store
        XCTAssertNil(store.pane(dp1.id))
    }

    func test_removeDrawerPane_updatesActiveIfRemoved() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "First")
        )!
        let dp2 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Second")
        )!

        // Active is dp2 (last added), remove dp2
        store.removeDrawerPane(dp2.id, from: pane.id)

        XCTAssertEqual(store.pane(pane.id)!.drawer!.activePaneId, dp1.id)
    }

    func test_removeDrawerPane_lastPane_resetsDrawerToEmpty() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )!

        store.removeDrawerPane(dp.id, from: pane.id)

        // Drawer resets to empty (always present on layout panes)
        let updated = store.pane(pane.id)!
        XCTAssertNotNil(updated.drawer)
        XCTAssertTrue(updated.drawer!.paneIds.isEmpty)
        XCTAssertNil(updated.drawer!.activePaneId)
    }

    func test_removeDrawerPane_invalidParent_noOp() {
        // Should not crash
        store.removeDrawerPane(UUID(), from: UUID())
    }

    // MARK: - toggleDrawer

    func test_toggleDrawer_collapsesWhenExpanded() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )

        store.toggleDrawer(for: pane.id)

        XCTAssertFalse(store.pane(pane.id)!.drawer!.isExpanded)
    }

    func test_toggleDrawer_expandsWhenCollapsed() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )
        store.toggleDrawer(for: pane.id)

        store.toggleDrawer(for: pane.id)

        XCTAssertTrue(store.pane(pane.id)!.drawer!.isExpanded)
    }

    func test_toggleDrawer_emptyDrawer_noOp() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Should not crash — empty drawer cannot be toggled
        store.toggleDrawer(for: pane.id)

        // Drawer still exists but empty
        XCTAssertNotNil(store.pane(pane.id)!.drawer)
        XCTAssertTrue(store.pane(pane.id)!.drawer!.paneIds.isEmpty)
    }

    // MARK: - setActiveDrawerPane

    func test_setActiveDrawerPane_switches() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "First")
        )!
        let dp2 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Second")
        )!

        store.setActiveDrawerPane(dp1.id, in: pane.id)

        XCTAssertEqual(store.pane(pane.id)!.drawer!.activePaneId, dp1.id)
    }

    func test_setActiveDrawerPane_invalidId_noOp() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )!

        store.setActiveDrawerPane(UUID(), in: pane.id)

        // Should remain unchanged
        XCTAssertEqual(store.pane(pane.id)!.drawer!.activePaneId, dp.id)
    }

    // MARK: - Persistence

    func test_drawer_persistsAndRestores() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "drawer-persist-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store1 = WorkspaceStore(persistor: persistor)

        let pane = store1.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store1.appendTab(tab)

        let dp = store1.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Persistent Drawer")
        )!
        store1.flush()

        // Restore into a new store
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        let restoredPane = store2.panes.values.first { !$0.isDrawerChild && $0.drawer != nil && !$0.drawer!.paneIds.isEmpty }
        XCTAssertNotNil(restoredPane, "Expected pane with non-empty drawer after restore")
        if let restored = restoredPane {
            XCTAssertEqual(restored.drawer!.paneIds.count, 1)
            XCTAssertEqual(restored.drawer!.activePaneId, dp.id)

            // Drawer child pane should also be restored in store
            let restoredDrawerPane = store2.pane(dp.id)
            XCTAssertNotNil(restoredDrawerPane, "Drawer child pane should be in store after restore")
            XCTAssertEqual(restoredDrawerPane?.metadata.title, "Persistent Drawer")
            XCTAssertTrue(restoredDrawerPane?.isDrawerChild ?? false)
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
