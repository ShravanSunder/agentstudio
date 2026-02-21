import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class DrawerCommandIntegrationTests {

    private var store: WorkspaceStore!
    private var viewRegistry: ViewRegistry!
    private var coordinator: TerminalViewCoordinator!
    private var runtime: SessionRuntime!
    private var executor: ActionExecutor!
    private var tempDir: URL!

    @BeforeEach
    func setUp() {
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

    @AfterEach
    func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        executor = nil
        coordinator = nil
        runtime = nil
        viewRegistry = nil
        store = nil
    }

    // MARK: - Helpers

    /// Creates a parent pane in a tab and returns the pane ID.
    @discardableResult
    private func createParentPaneInTab() -> (paneId: UUID, tabId: UUID) {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        return (pane.id, tab.id)
    }

    // MARK: - test_addDrawerPane_createsDrawerWithTerminalContent

    @Test

    func test_addDrawerPane_createsDrawerWithTerminalContent() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()

        // Act
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId))

        // Assert
        let parentPane = store.pane(parentPaneId)
        #expect((parentPane?.drawer) != nil)

        let drawer = parentPane!.drawer!
        #expect(drawer.paneIds.count == 1, "Drawer should contain exactly 1 pane")
        #expect(drawer.isExpanded)

        let drawerPaneId = drawer.paneIds[0]
        let drawerPane = store.pane(drawerPaneId)
        #expect((drawerPane) != nil)
        #expect(drawerPane?.metadata.title == "Drawer", "Drawer pane title should be 'Drawer'")
        #expect(drawer.activePaneId == drawerPaneId, "The new drawer pane should be active")
        #expect(drawerPane?.isDrawerChild ?? false)

        // Verify centralized defaults: zmx provider, persistent lifetime
        if case .terminal(let state) = drawerPane?.content {
            #expect(state.provider == .zmx, "Drawer panes should use zmx provider")
            #expect(state.lifetime == .persistent, "Drawer panes should be persistent")
        } else {
            Issue.record("Drawer pane content should be terminal")
        }
    }

    // MARK: - test_closeDrawerPane_removesActiveDrawerPane

    @Test

    func test_closeDrawerPane_removesActiveDrawerPane() {
        // Arrange — add 2 drawer panes
        let (parentPaneId, _) = createParentPaneInTab()

        let dp1 = store.addDrawerPane(to: parentPaneId)!
        let dp2 = store.addDrawerPane(to: parentPaneId)!
        #expect(store.pane(parentPaneId)!.drawer!.paneIds.count == 2)
        #expect(store.pane(parentPaneId)!.drawer!.activePaneId == dp2.id, "Last added drawer pane should be active initially")

        // Act — close the active drawer pane (dp2)
        executor.execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp2.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer
        #expect((drawer) != nil)
        #expect(drawer!.paneIds.count == 1, "Only 1 drawer pane should remain")
        #expect(drawer!.paneIds[0] == dp1.id, "The remaining pane should be dp1")
        #expect(drawer!.activePaneId == dp1.id, "dp1 should become the active drawer pane")
    }

    // MARK: - Toggle Drawer

    @Test

    func test_toggleDrawer_expandsCollapsedDrawer() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId)
        // Drawer auto-expands on add; collapse it first
        store.toggleDrawer(for: parentPaneId)
        #expect(!(store.pane(parentPaneId)!.drawer!.isExpanded))

        // Act
        executor.execute(.toggleDrawer(paneId: parentPaneId))

        // Assert
        #expect(store.pane(parentPaneId)!.drawer!.isExpanded)
    }

    @Test

    func test_toggleDrawer_collapsesExpandedDrawer() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId)
        #expect(store.pane(parentPaneId)!.drawer!.isExpanded)

        // Act
        executor.execute(.toggleDrawer(paneId: parentPaneId))

        // Assert
        #expect(!(store.pane(parentPaneId)!.drawer!.isExpanded))
    }

    // MARK: - Set Active Drawer Pane

    @Test

    func test_setActiveDrawerPane_switchesActivePaneId() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(to: parentPaneId)!
        let dp2 = store.addDrawerPane(to: parentPaneId)!
        #expect(store.pane(parentPaneId)!.drawer!.activePaneId == dp2.id)

        // Act
        executor.execute(.setActiveDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        #expect(store.pane(parentPaneId)!.drawer!.activePaneId == dp1.id)
    }

    // MARK: - Minimize / Expand Drawer Pane

    @Test

    func test_minimizeDrawerPane_hidesPane() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(to: parentPaneId)!
        store.addDrawerPane(to: parentPaneId)

        // Act
        executor.execute(.minimizeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        #expect(drawer.minimizedPaneIds.contains(dp1.id))
    }

    @Test

    func test_expandDrawerPane_restoresMinimizedPane() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp1 = store.addDrawerPane(to: parentPaneId)!
        store.addDrawerPane(to: parentPaneId)
        store.minimizeDrawerPane(dp1.id, in: parentPaneId)
        #expect(store.pane(parentPaneId)!.drawer!.minimizedPaneIds.contains(dp1.id))

        // Act
        executor.execute(.expandDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp1.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        #expect(!(drawer.minimizedPaneIds.contains(dp1.id)))
    }

    // MARK: - Resize / Equalize Drawer Panes

    @Test

    func test_resizeDrawerPane_updatesLayout() {
        // Arrange — create 2-pane drawer to get a split
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId)
        store.addDrawerPane(to: parentPaneId)

        let drawer = store.pane(parentPaneId)!.drawer!
        // Find the split node ID in the drawer layout
        guard case .split(let split) = drawer.layout.root else {
            Issue.record("Expected a split node in 2-pane drawer layout")
            return
        }
        let splitId = split.id

        // Act
        executor.execute(.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: 0.7))

        // Assert
        let updated = store.pane(parentPaneId)!.drawer!
        guard case .split(let updatedSplit) = updated.layout.root else {
            Issue.record("Expected split node after resize")
            return
        }
        #expect(updatedSplit.ratio == 0.7, accuracy: 0.001)
    }

    @Test

    func test_equalizeDrawerPanes_resetsRatios() {
        // Arrange — create 2-pane drawer and skew the ratio
        let (parentPaneId, _) = createParentPaneInTab()
        store.addDrawerPane(to: parentPaneId)
        store.addDrawerPane(to: parentPaneId)

        let drawer = store.pane(parentPaneId)!.drawer!
        guard case .split(let split) = drawer.layout.root else {
            Issue.record("Expected split")
            return
        }
        store.resizeDrawerPane(parentPaneId: parentPaneId, splitId: split.id, ratio: 0.8)

        // Act
        executor.execute(.equalizeDrawerPanes(parentPaneId: parentPaneId))

        // Assert
        let updated = store.pane(parentPaneId)!.drawer!
        guard case .split(let eqSplit) = updated.layout.root else {
            Issue.record("Expected split after equalize")
            return
        }
        #expect(eqSplit.ratio == 0.5, accuracy: 0.001)
    }

    // MARK: - Multi-Pane Drawer Lifecycle

    @Test

    func test_addMultipleDrawerPanes_buildsLayoutTree() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()

        // Act — add 3 drawer panes
        let dp1 = store.addDrawerPane(to: parentPaneId)!
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId))
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        #expect(drawer.paneIds.count == 3)
        #expect(drawer.paneIds.contains(dp1.id))
    }

    @Test

    func test_removeLastDrawerPane_leavesEmptyDrawer() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let dp = store.addDrawerPane(to: parentPaneId)!

        // Act
        executor.execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: dp.id))

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        #expect(drawer.paneIds.isEmpty)
        #expect((drawer.activePaneId) == nil)
        // Pane should be removed from store
        #expect((store.pane(dp.id)) == nil)
    }

    // MARK: - Close Parent Pane Cascades Drawer Children

    @Test

    func test_closeParentPane_removesDrawerChildren() {
        // Arrange — parent with 2 drawer children in a 2-pane tab
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.insertPane(p2.id, inTab: tab.id, at: p1.id, direction: .horizontal, position: .after)

        let dp1 = store.addDrawerPane(to: p1.id)!
        let dp2 = store.addDrawerPane(to: p1.id)!

        #expect((store.pane(dp1.id)) != nil)
        #expect((store.pane(dp2.id)) != nil)

        // Act — close the parent pane
        executor.execute(.closePane(tabId: tab.id, paneId: p1.id))

        // Assert — drawer children should be cascade-deleted
        #expect((store.pane(p1.id)) == nil)
        #expect((store.pane(dp1.id)) == nil)
        #expect((store.pane(dp2.id)) == nil)
    }

}
