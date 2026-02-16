import XCTest
@testable import AgentStudio

@MainActor
final class DrawerCommandIntegrationTests: XCTestCase {

    private var store: WorkspaceStore!
    private var viewRegistry: ViewRegistry!
    private var coordinator: TerminalViewCoordinator!
    private var runtime: SessionRuntime!
    private var executor: ActionExecutor!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "drawer-cmd-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(persistor: persistor)
        store.restore()
        viewRegistry = ViewRegistry()
        runtime = SessionRuntime(store: store)
        coordinator = TerminalViewCoordinator(store: store, viewRegistry: viewRegistry, runtime: runtime)
        executor = ActionExecutor(store: store, viewRegistry: viewRegistry, coordinator: coordinator)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        executor = nil
        coordinator = nil
        runtime = nil
        viewRegistry = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTerminalContent() -> PaneContent {
        .terminal(TerminalState(provider: .ghostty, lifetime: .temporary))
    }

    private func makeDrawerMetadata(title: String = "Drawer") -> PaneMetadata {
        PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: title)
    }

    /// Creates a parent pane in a tab and returns the pane ID.
    @discardableResult
    private func createParentPaneInTab() -> (paneId: UUID, tabId: UUID) {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        return (pane.id, tab.id)
    }

    // MARK: - test_addDrawerPane_createsDrawerWithTerminalContent

    func test_addDrawerPane_createsDrawerWithTerminalContent() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let content = makeTerminalContent()
        let metadata = makeDrawerMetadata(title: "My Terminal Drawer")

        // Act
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId, content: content, metadata: metadata))

        // Assert
        let parentPane = store.pane(parentPaneId)
        XCTAssertNotNil(parentPane?.drawer, "Drawer should exist on the parent pane")

        let drawer = parentPane!.drawer!
        XCTAssertEqual(drawer.paneIds.count, 1, "Drawer should contain exactly 1 pane")
        XCTAssertTrue(drawer.isExpanded, "Drawer should be expanded by default")

        let drawerPaneId = drawer.paneIds[0]
        let drawerPane = store.pane(drawerPaneId)
        XCTAssertNotNil(drawerPane, "Drawer pane should exist in store")
        XCTAssertEqual(drawerPane?.content, content, "Drawer pane content should be terminal")
        XCTAssertEqual(drawerPane?.metadata.title, "My Terminal Drawer", "Drawer pane title should match")
        XCTAssertEqual(drawer.activePaneId, drawerPaneId, "The new drawer pane should be active")
        XCTAssertTrue(drawerPane?.isDrawerChild ?? false, "Drawer pane should be a drawer child")
    }

    // MARK: - test_closeDrawerPane_removesActiveDrawerPane

    func test_closeDrawerPane_removesActiveDrawerPane() {
        // Arrange — add 2 drawer panes
        let (parentPaneId, _) = createParentPaneInTab()

        let dp1 = store.addDrawerPane(
            to: parentPaneId,
            content: makeTerminalContent(),
            metadata: makeDrawerMetadata(title: "First")
        )!
        let dp2 = store.addDrawerPane(
            to: parentPaneId,
            content: makeTerminalContent(),
            metadata: makeDrawerMetadata(title: "Second")
        )!
        XCTAssertEqual(store.pane(parentPaneId)!.drawer!.paneIds.count, 2)
        XCTAssertEqual(store.pane(parentPaneId)!.drawer!.activePaneId, dp2.id,
                        "Last added drawer pane should be active initially")

        // Act — close the active drawer pane (dp2)
        executor.execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp2.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer
        XCTAssertNotNil(drawer, "Drawer should still exist with remaining pane")
        XCTAssertEqual(drawer!.paneIds.count, 1, "Only 1 drawer pane should remain")
        XCTAssertEqual(drawer!.paneIds[0], dp1.id, "The remaining pane should be dp1")
        XCTAssertEqual(drawer!.activePaneId, dp1.id, "dp1 should become the active drawer pane")
    }

}
