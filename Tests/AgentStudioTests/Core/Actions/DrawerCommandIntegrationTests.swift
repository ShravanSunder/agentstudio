import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class DrawerCommandIntegrationTests {

    private var store: WorkspaceStore!
    private var viewRegistry: ViewRegistry!
    private var coordinator: PaneCoordinator!
    private var runtime: SessionRuntime!
    private var surfaceManager: MockPaneCoordinatorSurfaceManager!
    private var executor: ActionExecutor!
    private var tempDir: URL!

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "drawer-cmd-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(persistor: persistor)
        store.restore()
        viewRegistry = ViewRegistry()
        runtime = SessionRuntime(store: store)
        surfaceManager = MockPaneCoordinatorSurfaceManager()
        coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        executor = ActionExecutor(coordinator: coordinator)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
        executor = nil
        surfaceManager = nil
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

    // MARK: - test_addDrawerPane_rollsBackWhenTerminalViewCreationFails

    @Test

    func test_addDrawerPane_rollsBackWhenTerminalViewCreationFails() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()
        let paneCountBefore = store.panes.count

        // Act
        executor.execute(.addDrawerPane(parentPaneId: parentPaneId))

        // Assert — with a failing surface manager, command must rollback.
        let parentPane = store.pane(parentPaneId)
        #expect((parentPane?.drawer) != nil)
        #expect(parentPane!.drawer!.paneIds.isEmpty, "Drawer should remain empty after rollback")
        #expect(store.panes.count == paneCountBefore, "No orphan drawer pane should remain in store")
    }

    // MARK: - test_closeDrawerPane_removesActiveDrawerPane

    @Test

    func test_closeDrawerPane_removesActiveDrawerPane() {
        // Arrange — add 2 drawer panes
        let (parentPaneId, _) = createParentPaneInTab()

        let dp1 = store.addDrawerPane(to: parentPaneId)!
        let dp2 = store.addDrawerPane(to: parentPaneId)!
        #expect(store.pane(parentPaneId)!.drawer!.paneIds.count == 2)
        #expect(
            store.pane(parentPaneId)!.drawer!.activePaneId == dp2.id,
            "Last added drawer pane should be active initially")

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
        #expect(abs((updatedSplit.ratio) - (0.7)) <= 0.001)
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
        #expect(abs((eqSplit.ratio) - (0.5)) <= 0.001)
    }

    // MARK: - Multi-Pane Drawer Lifecycle

    @Test

    func test_addMultipleDrawerPanes_buildsLayoutTree() {
        // Arrange
        let (parentPaneId, _) = createParentPaneInTab()

        // Act — add 3 drawer panes
        let dp1 = store.addDrawerPane(to: parentPaneId)!
        let dp2 = store.addDrawerPane(to: parentPaneId)!
        let dp3 = store.addDrawerPane(to: parentPaneId)!

        // Assert
        let drawer = store.pane(parentPaneId)!.drawer!
        #expect(drawer.paneIds.count == 3)
        #expect(drawer.paneIds.contains(dp1.id))
        #expect(drawer.paneIds.contains(dp2.id))
        #expect(drawer.paneIds.contains(dp3.id))
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

@MainActor
private final class MockPaneCoordinatorSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let stream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        stream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { stream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
