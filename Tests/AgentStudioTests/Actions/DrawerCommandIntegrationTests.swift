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
        XCTAssertNotNil(parentPane?.drawer, "Drawer should be created on the parent pane")

        let drawer = parentPane!.drawer!
        XCTAssertEqual(drawer.panes.count, 1, "Drawer should contain exactly 1 pane")
        XCTAssertTrue(drawer.isExpanded, "Drawer should be expanded by default")

        let drawerPane = drawer.panes[0]
        XCTAssertEqual(drawerPane.content, content, "Drawer pane content should be terminal")
        XCTAssertEqual(drawerPane.metadata.title, "My Terminal Drawer", "Drawer pane title should match")
        XCTAssertEqual(drawer.activeDrawerPaneId, drawerPane.id, "The new drawer pane should be active")
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
        XCTAssertEqual(store.pane(parentPaneId)!.drawer!.panes.count, 2)
        XCTAssertEqual(store.pane(parentPaneId)!.drawer!.activeDrawerPaneId, dp1.id,
                        "First drawer pane should be active initially")

        // Act — close the active drawer pane (dp1)
        executor.execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer
        XCTAssertNotNil(drawer, "Drawer should still exist with remaining pane")
        XCTAssertEqual(drawer!.panes.count, 1, "Only 1 drawer pane should remain")
        XCTAssertEqual(drawer!.panes[0].id, dp2.id, "The remaining pane should be dp2")
        XCTAssertEqual(drawer!.activeDrawerPaneId, dp2.id, "dp2 should become the active drawer pane")
    }

    // MARK: - test_toggleDrawer_cyclesExpandedState

    func test_toggleDrawer_cyclesExpandedState() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        _ = store.addDrawerPane(
            to: parentPaneId,
            content: makeTerminalContent(),
            metadata: makeDrawerMetadata()
        )
        XCTAssertTrue(store.pane(parentPaneId)!.drawer!.isExpanded, "Precondition: drawer starts expanded")

        // Act & Assert — toggle 1: collapse
        executor.execute(.toggleDrawer(paneId: parentPaneId))
        XCTAssertFalse(store.pane(parentPaneId)!.drawer!.isExpanded,
                        "After 1st toggle, drawer should be collapsed")

        // Act & Assert — toggle 2: expand
        executor.execute(.toggleDrawer(paneId: parentPaneId))
        XCTAssertTrue(store.pane(parentPaneId)!.drawer!.isExpanded,
                       "After 2nd toggle, drawer should be expanded")

        // Act & Assert — toggle 3: collapse again
        executor.execute(.toggleDrawer(paneId: parentPaneId))
        XCTAssertFalse(store.pane(parentPaneId)!.drawer!.isExpanded,
                        "After 3rd toggle, drawer should be collapsed")
    }

    // MARK: - test_setActiveDrawerPane_invalidId_noOp

    func test_setActiveDrawerPane_invalidId_noOp() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(
            to: parentPaneId,
            content: makeTerminalContent(),
            metadata: makeDrawerMetadata(title: "Only")
        )!
        let originalActiveId = store.pane(parentPaneId)!.drawer!.activeDrawerPaneId
        XCTAssertEqual(originalActiveId, dp1.id)

        // Act — try to set active to a non-existent drawer pane ID
        let bogusId = UUID()
        executor.execute(.setActiveDrawerPane(parentPaneId: parentPaneId, drawerPaneId: bogusId))

        // Assert — no change
        let drawer = store.pane(parentPaneId)!.drawer!
        XCTAssertEqual(drawer.activeDrawerPaneId, dp1.id,
                        "Active drawer pane should remain unchanged when setting invalid ID")
        XCTAssertEqual(drawer.panes.count, 1, "Pane count should remain unchanged")
    }

    // MARK: - test_addMultipleDrawerPanes_firstBecomesActive

    func test_addMultipleDrawerPanes_firstBecomesActive() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let content = makeTerminalContent()

        // Act — add 3 drawer panes via executor
        executor.execute(.addDrawerPane(
            parentPaneId: parentPaneId,
            content: content,
            metadata: makeDrawerMetadata(title: "First")
        ))
        executor.execute(.addDrawerPane(
            parentPaneId: parentPaneId,
            content: content,
            metadata: makeDrawerMetadata(title: "Second")
        ))
        executor.execute(.addDrawerPane(
            parentPaneId: parentPaneId,
            content: content,
            metadata: makeDrawerMetadata(title: "Third")
        ))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        XCTAssertEqual(drawer.panes.count, 3, "All 3 drawer panes should be present")

        let firstPaneId = drawer.panes[0].id
        XCTAssertEqual(drawer.activeDrawerPaneId, firstPaneId,
                        "The first drawer pane added should remain the active one")
        XCTAssertEqual(drawer.panes[0].metadata.title, "First")
        XCTAssertEqual(drawer.panes[1].metadata.title, "Second")
        XCTAssertEqual(drawer.panes[2].metadata.title, "Third")
    }
}
