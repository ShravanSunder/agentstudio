import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreDrawerTests {

    private var store: WorkspaceStore!

    @BeforeEach
    func setUp() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - addDrawerPane

    @Test

    func test_addDrawerPane_createsDrawerChild() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Act
        let dp = store.addDrawerPane(to: pane.id)

        // Assert
        #expect((dp) != nil)
        let updated = store.pane(pane.id)!
        #expect((updated.drawer) != nil)
        #expect(updated.drawer!.paneIds.count == 1)
        #expect(updated.drawer!.paneIds[0] == dp!.id)
        #expect(updated.drawer!.activePaneId == dp!.id)
        #expect(updated.drawer!.isExpanded)

        // Drawer pane is a real entry in store.panes
        let drawerPaneInStore = store.pane(dp!.id)
        #expect((drawerPaneInStore) != nil)
        #expect(drawerPaneInStore!.isDrawerChild)
        #expect(drawerPaneInStore!.parentPaneId == pane.id)
    }

    @Test

    func test_addDrawerPane_appendsToExistingDrawer() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!

        let dp2 = store.addDrawerPane(to: pane.id)!

        let updated = store.pane(pane.id)!
        #expect(updated.drawer!.paneIds.count == 2)
        #expect(updated.drawer!.activePaneId == dp2.id)  // last added becomes active
        #expect(updated.drawer!.paneIds[1] == dp2.id)

        // Both drawer panes are in the layout
        #expect(updated.drawer!.layout.contains(dp1.id))
        #expect(updated.drawer!.layout.contains(dp2.id))
    }

    @Test

    func test_addDrawerPane_invalidParent_returnsNil() {
        let dp = store.addDrawerPane(to: UUID())

        #expect((dp) == nil)
    }

    @Test

    func test_addDrawerPane_marksDirty() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.flush()

        _ = store.addDrawerPane(to: pane.id)

        #expect(store.isDirty)
    }

    // MARK: - removeDrawerPane

    @Test

    func test_removeDrawerPane_removesFromDrawer() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        store.removeDrawerPane(dp1.id, from: pane.id)

        let updated = store.pane(pane.id)!
        #expect(updated.drawer!.paneIds.count == 1)
        #expect(updated.drawer!.paneIds[0] == dp2.id)

        // dp1 removed from store
        #expect((store.pane(dp1.id)) == nil)
    }

    @Test

    func test_removeDrawerPane_updatesActiveIfRemoved() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        // Active is dp2 (last added), remove dp2
        store.removeDrawerPane(dp2.id, from: pane.id)

        #expect(store.pane(pane.id)!.drawer!.activePaneId == dp1.id)
    }

    @Test

    func test_removeDrawerPane_lastPane_resetsDrawerToEmpty() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(to: pane.id)!

        store.removeDrawerPane(dp.id, from: pane.id)

        // Drawer resets to empty (always present on layout panes)
        let updated = store.pane(pane.id)!
        #expect((updated.drawer) != nil)
        #expect(updated.drawer!.paneIds.isEmpty)
        #expect((updated.drawer!.activePaneId) == nil)
    }

    @Test

    func test_removeDrawerPane_invalidParent_noOp() {
        // Should not crash
        store.removeDrawerPane(UUID(), from: UUID())
    }

    // MARK: - toggleDrawer

    @Test

    func test_toggleDrawer_collapsesWhenExpanded() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(to: pane.id)

        store.toggleDrawer(for: pane.id)

        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))
    }

    @Test

    func test_toggleDrawer_expandsWhenCollapsed() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(to: pane.id)
        store.toggleDrawer(for: pane.id)

        store.toggleDrawer(for: pane.id)

        #expect(store.pane(pane.id)!.drawer!.isExpanded)
    }

    @Test

    func test_toggleDrawer_emptyDrawer_expandsAndCollapses() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))

        // Act — expand empty drawer
        store.toggleDrawer(for: pane.id)

        // Assert — expanded even though empty
        #expect(store.pane(pane.id)!.drawer!.isExpanded)
        #expect(store.pane(pane.id)!.drawer!.paneIds.isEmpty)

        // Act — collapse again
        store.toggleDrawer(for: pane.id)

        // Assert
        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))
    }

    @Test

    func test_toggleDrawer_emptyDrawer_collapsesOtherDrawers() {
        // Arrange — two panes, expand one drawer
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(to: pane1.id)
        // pane1 drawer is expanded (addDrawerPane sets isExpanded = true)

        // Act — toggle empty pane2 drawer (should collapse pane1's drawer)
        store.toggleDrawer(for: pane2.id)

        // Assert
        #expect(store.pane(pane2.id)!.drawer!.isExpanded)
        #expect(!(store.pane(pane1.id)!.drawer!.isExpanded))
    }

    // MARK: - setActiveDrawerPane

    @Test

    func test_setActiveDrawerPane_switches() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        store.setActiveDrawerPane(dp1.id, in: pane.id)

        #expect(store.pane(pane.id)!.drawer!.activePaneId == dp1.id)
    }

    @Test

    func test_setActiveDrawerPane_invalidId_noOp() {
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(to: pane.id)!

        store.setActiveDrawerPane(UUID(), in: pane.id)

        // Should remain unchanged
        #expect(store.pane(pane.id)!.drawer!.activePaneId == dp.id)
    }

    // MARK: - resizeDrawerPane

    @Test

    func test_resizeDrawerPane_updatesLayout() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        // Find the split ID
        let drawer = store.pane(pane.id)!.drawer!
        guard case .split(let split) = drawer.layout.root else {
            Issue.record("Expected split layout with 2 drawer panes")
            return
        }

        // Act
        store.resizeDrawerPane(parentPaneId: pane.id, splitId: split.id, ratio: 0.7)

        // Assert
        let updated = store.pane(pane.id)!.drawer!
        #expect(updated.layout.ratioForSplit(split.id) ?? 0 == 0.7, accuracy: 0.01)
    }

    @Test

    func test_equalizeDrawerPanes_resetsRatios() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(to: pane.id)
        _ = store.addDrawerPane(to: pane.id)

        let drawer = store.pane(pane.id)!.drawer!
        guard case .split(let split) = drawer.layout.root else {
            Issue.record("Expected split layout")
            return
        }
        store.resizeDrawerPane(parentPaneId: pane.id, splitId: split.id, ratio: 0.8)

        // Act
        store.equalizeDrawerPanes(parentPaneId: pane.id)

        // Assert
        let updated = store.pane(pane.id)!.drawer!
        #expect(updated.layout.ratioForSplit(split.id) ?? 0 == 0.5, accuracy: 0.01)
    }

    // MARK: - minimizeDrawerPane / expandDrawerPane

    @Test

    func test_minimizeDrawerPane_returnsTrue_onSuccess() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        _ = store.addDrawerPane(to: pane.id)

        // Act
        let result = store.minimizeDrawerPane(dp1.id, in: pane.id)

        // Assert
        #expect(result)
    }

    @Test

    func test_minimizeDrawerPane_succeeds_lastVisiblePane() {
        // Arrange — single drawer pane
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(to: pane.id)!

        // Act
        let result = store.minimizeDrawerPane(dp.id, in: pane.id)

        // Assert — minimizing last pane is now allowed
        #expect(result)
        #expect(store.pane(pane.id)!.drawer!.minimizedPaneIds.contains(dp.id))
        #expect((store.pane(pane.id)!.drawer!.activePaneId) == nil)
    }

    @Test

    func test_minimizeDrawerPane_returnsFalse_invalidPaneId() {
        // Act
        let result = store.minimizeDrawerPane(UUID(), in: UUID())

        // Assert
        #expect(!(result))
    }

    @Test

    func test_minimizeDrawerPane_addsToMinimizedSet() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        // Act
        store.minimizeDrawerPane(dp1.id, in: pane.id)

        // Assert
        let drawer = store.pane(pane.id)!.drawer!
        #expect(drawer.minimizedPaneIds.contains(dp1.id))
        #expect(!(drawer.minimizedPaneIds.contains(dp2.id)))
    }

    @Test

    func test_minimizeDrawerPane_lastVisible_succeeds() {
        // Arrange — single drawer pane
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(to: pane.id)!

        // Act — minimize the only pane
        store.minimizeDrawerPane(dp.id, in: pane.id)

        // Assert — minimizing last pane is now allowed
        #expect(store.pane(pane.id)!.drawer!.minimizedPaneIds.contains(dp.id))
        #expect((store.pane(pane.id)!.drawer!.activePaneId) == nil)
    }

    @Test

    func test_minimizeDrawerPane_switchesActiveIfMinimized() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!
        // dp2 is active (last added)

        // Act — minimize the active pane
        store.minimizeDrawerPane(dp2.id, in: pane.id)

        // Assert — active should switch to dp1
        #expect(store.pane(pane.id)!.drawer!.activePaneId == dp1.id)
    }

    @Test

    func test_expandDrawerPane_removesFromMinimizedSet() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        _ = store.addDrawerPane(to: pane.id)
        store.minimizeDrawerPane(dp1.id, in: pane.id)
        #expect(store.pane(pane.id)!.drawer!.minimizedPaneIds.contains(dp1.id))

        // Act
        store.expandDrawerPane(dp1.id, in: pane.id)

        // Assert
        #expect(!(store.pane(pane.id)!.drawer!.minimizedPaneIds.contains(dp1.id)))
    }

    // MARK: - Cascade Deletion

    @Test

    func test_removePane_cascadeDeletesDrawerChildren() {
        // Arrange — parent pane with 2 drawer children
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        // Precondition: all 3 panes exist
        #expect((store.pane(pane.id)) != nil)
        #expect((store.pane(dp1.id)) != nil)
        #expect((store.pane(dp2.id)) != nil)

        // Act — remove the parent pane
        store.removePane(pane.id)

        // Assert — parent and both drawer children should be gone
        #expect((store.pane(pane.id)) == nil)
        #expect((store.pane(dp1.id)) == nil)
        #expect((store.pane(dp2.id)) == nil)
    }

    @Test

    func test_removeLastDrawerPane_preservesIsExpanded() {
        // Arrange — collapsed drawer with one pane
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(to: pane.id)!
        // Collapse the drawer
        store.toggleDrawer(for: pane.id)
        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))

        // Act — remove the last drawer pane
        store.removeDrawerPane(dp.id, from: pane.id)

        // Assert — isExpanded should be preserved (still false)
        let drawer = store.pane(pane.id)!.drawer!
        #expect(drawer.paneIds.isEmpty)
        #expect(!(drawer.isExpanded))
    }

    @Test

    func test_withDrawer_drawerChildPane_noOp() {
        // Arrange — create a drawer child pane
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let dp = store.addDrawerPane(to: pane.id)!

        // Act — try to mutate drawer on a drawer child (should be no-op)
        var drawerChild = store.pane(dp.id)!
        var mutationCalled = false
        drawerChild.withDrawer { _ in
            mutationCalled = true
        }

        // Assert — mutation should not have been called (drawer children have no drawer)
        #expect(!(mutationCalled))
        #expect((drawerChild.drawer) == nil)
    }

    // MARK: - collapseAllDrawers

    @Test

    func test_collapseAllDrawers_collapsesExpandedDrawers() {
        // Arrange — two panes with expanded drawers
        let pane1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(to: pane1.id)
        store.toggleDrawer(for: pane2.id)  // expand empty drawer
        #expect(store.pane(pane2.id)!.drawer!.isExpanded)

        // Act
        store.collapseAllDrawers()

        // Assert
        #expect(!(store.pane(pane1.id)!.drawer!.isExpanded))
        #expect(!(store.pane(pane2.id)!.drawer!.isExpanded))
    }

    @Test

    func test_collapseAllDrawers_noOp_whenNoneExpanded() {
        // Arrange — pane with collapsed drawer
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))

        // Act — should not crash
        store.collapseAllDrawers()

        // Assert
        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))
    }

    // MARK: - Persistence

    @Test

    func test_drawer_persistsAndRestores() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "drawer-persist-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store1 = WorkspaceStore(persistor: persistor)

        let pane = store1.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store1.appendTab(tab)

        let dp = store1.addDrawerPane(to: pane.id)!
        store1.flush()

        // Restore into a new store
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        let restoredPane = store2.panes.values.first {
            !$0.isDrawerChild && $0.drawer != nil && !$0.drawer!.paneIds.isEmpty
        }
        #expect((restoredPane) != nil)
        if let restored = restoredPane {
            #expect(restored.drawer!.paneIds.count == 1)
            #expect(restored.drawer!.activePaneId == dp.id)

            // Drawer child pane should also be restored in store
            let restoredDrawerPane = store2.pane(dp.id)
            #expect((restoredDrawerPane) != nil)
            #expect(restoredDrawerPane?.metadata.title == "Drawer")
            #expect(restoredDrawerPane?.isDrawerChild ?? false)
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
