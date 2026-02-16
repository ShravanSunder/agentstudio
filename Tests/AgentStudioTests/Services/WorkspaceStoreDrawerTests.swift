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

    func test_addDrawerPane_createsDrawer() {
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
        XCTAssertEqual(updated.drawer!.panes.count, 1)
        XCTAssertEqual(updated.drawer!.panes[0].id, dp!.id)
        XCTAssertEqual(updated.drawer!.activeDrawerPaneId, dp!.id)
        XCTAssertTrue(updated.drawer!.isExpanded)
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
        XCTAssertEqual(updated.drawer!.panes.count, 2)
        XCTAssertEqual(updated.drawer!.activeDrawerPaneId, dp2.id) // last added becomes active
        XCTAssertEqual(updated.drawer!.panes[1].id, dp2.id)
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
        XCTAssertEqual(updated.drawer!.panes.count, 1)
        XCTAssertEqual(updated.drawer!.panes[0].id, dp2.id)
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

        // Active is dp1, remove dp1
        store.removeDrawerPane(dp1.id, from: pane.id)

        XCTAssertEqual(store.pane(pane.id)!.drawer!.activeDrawerPaneId, dp2.id)
    }

    func test_removeDrawerPane_lastPane_removesDrawer() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil))
        )!

        store.removeDrawerPane(dp.id, from: pane.id)

        XCTAssertNil(store.pane(pane.id)!.drawer)
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

    func test_toggleDrawer_noDrawer_noOp() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Should not crash
        store.toggleDrawer(for: pane.id)

        XCTAssertNil(store.pane(pane.id)!.drawer)
    }

    // MARK: - setActiveDrawerPane

    func test_setActiveDrawerPane_switches() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "First")
        )
        let dp2 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Second")
        )!

        store.setActiveDrawerPane(dp2.id, in: pane.id)

        XCTAssertEqual(store.pane(pane.id)!.drawer!.activeDrawerPaneId, dp2.id)
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
        XCTAssertEqual(store.pane(pane.id)!.drawer!.activeDrawerPaneId, dp.id)
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

        let restoredPane = store2.panes.values.first { $0.drawer != nil }
        XCTAssertNotNil(restoredPane, "Expected pane with drawer after restore")
        if let restored = restoredPane {
            XCTAssertEqual(restored.drawer!.panes.count, 1)
            XCTAssertEqual(restored.drawer!.panes[0].metadata.title, "Persistent Drawer")
            XCTAssertEqual(restored.drawer!.activeDrawerPaneId, dp.id)
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
