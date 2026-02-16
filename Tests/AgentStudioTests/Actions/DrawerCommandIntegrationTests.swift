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

    // MARK: - Toggle Drawer

    func test_toggleDrawer_expandsCollapsedDrawer() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata())
        // Drawer auto-expands on add; collapse it first
        store.toggleDrawer(for: parentPaneId)
        XCTAssertFalse(store.pane(parentPaneId)!.drawer!.isExpanded)

        // Act
        executor.execute(.toggleDrawer(paneId: parentPaneId))

        // Assert
        XCTAssertTrue(store.pane(parentPaneId)!.drawer!.isExpanded)
    }

    func test_toggleDrawer_collapsesExpandedDrawer() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata())
        XCTAssertTrue(store.pane(parentPaneId)!.drawer!.isExpanded)

        // Act
        executor.execute(.toggleDrawer(paneId: parentPaneId))

        // Assert
        XCTAssertFalse(store.pane(parentPaneId)!.drawer!.isExpanded)
    }

    // MARK: - Set Active Drawer Pane

    func test_setActiveDrawerPane_switchesActivePaneId() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "A"))!
        let dp2 = store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "B"))!
        XCTAssertEqual(store.pane(parentPaneId)!.drawer!.activePaneId, dp2.id)

        // Act
        executor.execute(.setActiveDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        XCTAssertEqual(store.pane(parentPaneId)!.drawer!.activePaneId, dp1.id)
    }

    // MARK: - Minimize / Expand Drawer Pane

    func test_minimizeDrawerPane_hidesPane() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "A"))!
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "B"))

        // Act
        executor.execute(.minimizeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        XCTAssertTrue(drawer.minimizedPaneIds.contains(dp1.id))
    }

    func test_expandDrawerPane_restoresMinimizedPane() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "A"))!
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "B"))
        store.minimizeDrawerPane(dp1.id, in: parentPaneId)
        XCTAssertTrue(store.pane(parentPaneId)!.drawer!.minimizedPaneIds.contains(dp1.id))

        // Act
        executor.execute(.expandDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        XCTAssertFalse(drawer.minimizedPaneIds.contains(dp1.id))
    }

    // MARK: - Resize / Equalize Drawer Panes

    func test_resizeDrawerPane_updatesLayout() {
        // Arrange — create 2-pane drawer to get a split
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "A"))
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "B"))

        let drawer = store.pane(parentPaneId)!.drawer!
        // Find the split node ID in the drawer layout
        guard case .split(let split) = drawer.layout.root else {
            XCTFail("Expected a split node in 2-pane drawer layout")
            return
        }
        let splitId = split.id

        // Act
        executor.execute(.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: 0.7))

        // Assert
        let updated = store.pane(parentPaneId)!.drawer!
        guard case .split(let updatedSplit) = updated.layout.root else {
            XCTFail("Expected split node after resize")
            return
        }
        XCTAssertEqual(updatedSplit.ratio, 0.7, accuracy: 0.001)
    }

    func test_equalizeDrawerPanes_resetsRatios() {
        // Arrange — create 2-pane drawer and skew the ratio
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "A"))
        store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "B"))

        let drawer = store.pane(parentPaneId)!.drawer!
        guard case .split(let split) = drawer.layout.root else {
            XCTFail("Expected split")
            return
        }
        store.resizeDrawerPane(parentPaneId: parentPaneId, splitId: split.id, ratio: 0.8)

        // Act
        executor.execute(.equalizeDrawerPanes(parentPaneId: parentPaneId))

        // Assert
        let updated = store.pane(parentPaneId)!.drawer!
        guard case .split(let eqSplit) = updated.layout.root else {
            XCTFail("Expected split after equalize")
            return
        }
        XCTAssertEqual(eqSplit.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Multi-Pane Drawer Lifecycle

    func test_addMultipleDrawerPanes_buildsLayoutTree() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()

        // Act — add 3 drawer panes
        let dp1 = store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "A"))!
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "B")))
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "C")))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        XCTAssertEqual(drawer.paneIds.count, 3)
        XCTAssertTrue(drawer.paneIds.contains(dp1.id))
    }

    func test_removeLastDrawerPane_leavesEmptyDrawer() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp = store.addDrawerPane(to: parentPaneId, content: makeTerminalContent(), metadata: makeDrawerMetadata())!

        // Act
        executor.execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        XCTAssertTrue(drawer.paneIds.isEmpty)
        XCTAssertNil(drawer.activePaneId)
        // Pane should be removed from store
        XCTAssertNil(store.pane(dp.id))
    }

    // MARK: - Close Parent Pane Cascades Drawer Children

    func test_closeParentPane_removesDrawerChildren() {
        // Arrange — parent with 2 drawer children in a 2-pane tab
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.insertPane(p2.id, inTab: tab.id, at: p1.id, direction: .horizontal, position: .after)

        let dp1 = store.addDrawerPane(to: p1.id, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "Child1"))!
        let dp2 = store.addDrawerPane(to: p1.id, content: makeTerminalContent(), metadata: makeDrawerMetadata(title: "Child2"))!

        XCTAssertNotNil(store.pane(dp1.id))
        XCTAssertNotNil(store.pane(dp2.id))

        // Act — close the parent pane
        executor.execute(.closePane(tabId: tab.id, paneId: p1.id))

        // Assert — drawer children should be cascade-deleted
        XCTAssertNil(store.pane(p1.id))
        XCTAssertNil(store.pane(dp1.id), "Drawer child dp1 should be cascade-deleted")
        XCTAssertNil(store.pane(dp2.id), "Drawer child dp2 should be cascade-deleted")
    }

}
