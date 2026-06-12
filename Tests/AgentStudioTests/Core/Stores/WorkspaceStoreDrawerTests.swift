import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreDrawerTests {

    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    private func drawerView(for parentPaneId: UUID) -> DrawerView? {
        store.drawerView(forParent: parentPaneId)
    }

    private func createTabbedPane() -> Pane {
        let pane = store.createPane()
        store.appendTab(Tab(paneId: pane.id))
        return pane
    }

    private func saveLiveWorkspaceSnapshotToSQLite() async throws {
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.drawer.save.core.\(UUID().uuidString)"
        )
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.drawer.save.local.\(UUID().uuidString)"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            }
        )
        let snapshot = WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(
            identityAtom: store.identityAtom,
            windowMemoryAtom: store.windowMemoryAtom,
            repositoryTopologyAtom: store.repositoryTopologyAtom,
            workspacePaneAtom: store.paneAtom,
            workspaceTabLayoutAtom: store.tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        try await datastore.saveWorkspaceSnapshot(snapshot)
    }

    // MARK: - addDrawerPane

    @Test

    func test_addDrawerPane_createsDrawerChild() {
        // Arrange
        let pane = createTabbedPane()

        // Act
        let dp = store.addDrawerPane(to: pane.id)

        // Assert
        #expect((dp) != nil)
        let updated = store.pane(pane.id)!
        #expect((updated.drawer) != nil)
        #expect(updated.drawer!.paneIds.count == 1)
        #expect(updated.drawer!.paneIds[0] == dp!.id)
        #expect(drawerView(for: pane.id)?.activeChildId == dp!.id)
        #expect(updated.drawer!.isExpanded)

        // Drawer pane is a real entry in store.panes
        let drawerPaneInStore = store.pane(dp!.id)
        #expect((drawerPaneInStore) != nil)
        #expect(drawerPaneInStore!.isDrawerChild)
        #expect(drawerPaneInStore!.parentPaneId == pane.id)
    }

    @Test
    func test_addDrawerPane_addsDrawerChildToTabMembership() throws {
        let pane = createTabbedPane()

        let drawerPane = try #require(store.addDrawerPane(to: pane.id))

        let tab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))
        #expect(tab.allPaneIds.contains(drawerPane.id))
    }

    @Test
    func test_addDrawerPane_liveWorkspaceSnapshotSavesToSQLite() async throws {
        let pane = createTabbedPane()

        _ = try #require(store.addDrawerPane(to: pane.id))

        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test

    func test_addDrawerPane_appendsToExistingDrawer() {
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!

        let dp2 = store.addDrawerPane(to: pane.id)!

        let updated = store.pane(pane.id)!
        #expect(updated.drawer!.paneIds.count == 2)
        #expect(drawerView(for: pane.id)?.activeChildId == dp2.id)  // last added becomes active
        #expect(updated.drawer!.paneIds[1] == dp2.id)

        // Both drawer panes are in the layout
        #expect(drawerView(for: pane.id)?.layout.contains(dp1.id) == true)
        #expect(drawerView(for: pane.id)?.layout.contains(dp2.id) == true)
    }

    @Test
    func test_removeDrawerPane_redistributesRemainingRatiosProportionally() {
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!
        let dp3 = store.addDrawerPane(to: pane.id)!

        store.removeDrawerPane(dp2.id, from: pane.id)

        let updatedLayout = drawerView(for: pane.id)!.layout.topRow
        #expect(updatedLayout.paneIds == [dp1.id, dp3.id])
        expectApprox(updatedLayout.ratios, [0.666666666667, 0.333333333333])
    }

    @Test

    func test_addDrawerPane_invalidParent_returnsNil() {
        let dp = store.addDrawerPane(to: UUID())

        #expect((dp) == nil)
    }

    private func expectApprox(
        _ actual: [Double],
        _ expected: [Double],
        tolerance: Double = 0.000001,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        for (actualRatio, expectedRatio) in zip(actual, expected) {
            #expect(abs(actualRatio - expectedRatio) < tolerance, sourceLocation: sourceLocation)
        }
        #expect(abs(actual.reduce(0, +) - 1.0) < tolerance, sourceLocation: sourceLocation)
    }

    @Test

    func test_addDrawerPane_marksDirty() {
        let pane = createTabbedPane()
        store.flush()

        _ = store.addDrawerPane(to: pane.id)

        #expect(store.isDirty)
    }

    @Test
    func test_addDrawerPane_inheritsParentWorktreeContext() throws {
        let repoPath = URL(filePath: "/tmp/drawer-parent-repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "feature-branch")
        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "feature-branch", path: worktreePath)
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let inheritedCWD = worktreePath.appending(path: "Sources")
        let parent = store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: inheritedCWD
            )
        )

        let drawerPane = try #require(store.addDrawerPane(to: parent.id))

        #expect(drawerPane.isDrawerChild)
        #expect(drawerPane.parentPaneId == parent.id)
        #expect(drawerPane.repoId == repo.id)
        #expect(drawerPane.worktreeId == worktree.id)
        #expect(drawerPane.metadata.cwd == inheritedCWD)
        #expect(drawerPane.metadata.launchDirectory == inheritedCWD)
    }

    @Test
    func test_insertDrawerPane_inheritsParentWorktreeContext() throws {
        let repoPath = URL(filePath: "/tmp/drawer-insert-parent-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "feature-branch")
        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "feature-branch", path: worktreePath)
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let inheritedCWD = worktreePath.appending(path: "Sources")
        let parent = store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: inheritedCWD
            )
        )

        let firstDrawerPane = try #require(store.addDrawerPane(to: parent.id))
        let insertedDrawerPane = try #require(
            store.insertDrawerPane(
                in: parent.id,
                at: firstDrawerPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
        )

        #expect(insertedDrawerPane.isDrawerChild)
        #expect(insertedDrawerPane.parentPaneId == parent.id)
        #expect(insertedDrawerPane.repoId == repo.id)
        #expect(insertedDrawerPane.worktreeId == worktree.id)
        #expect(insertedDrawerPane.metadata.cwd == inheritedCWD)
        #expect(insertedDrawerPane.metadata.launchDirectory == inheritedCWD)
    }

    @Test
    func test_insertDrawerPane_downCreatesSecondRow() throws {
        let parent = createTabbedPane()
        let first = try #require(store.addDrawerPane(to: parent.id))

        let second = try #require(
            store.insertDrawerPane(
                in: parent.id,
                at: first.id,
                direction: .vertical,
                position: .after, sizingMode: .halveTarget
            )
        )

        let view = try #require(drawerView(for: parent.id))
        #expect(view.layout.bottomRow?.contains(second.id) == true)
        #expect(view.layout.topRow.contains(first.id))
    }

    @Test
    func test_insertDrawerPane_liveWorkspaceSnapshotSavesToSQLite() async throws {
        let parent = createTabbedPane()
        let first = try #require(store.addDrawerPane(to: parent.id))

        _ = try #require(
            store.insertDrawerPane(
                in: parent.id,
                at: first.id,
                direction: .vertical,
                position: .after,
                sizingMode: .halveTarget
            )
        )

        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    // MARK: - removeDrawerPane

    @Test

    func test_removeDrawerPane_removesFromDrawer() {
        let pane = createTabbedPane()
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
    func test_removeDrawerPane_removesDrawerChildFromTabMembership() throws {
        let pane = createTabbedPane()
        let drawerPane = try #require(store.addDrawerPane(to: pane.id))

        store.removeDrawerPane(drawerPane.id, from: pane.id)

        let tab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))
        #expect(!tab.allPaneIds.contains(drawerPane.id))
    }

    @Test
    func test_removeDrawerPane_liveWorkspaceSnapshotSavesToSQLite() async throws {
        let pane = createTabbedPane()
        _ = try #require(store.addDrawerPane(to: pane.id))
        let remainingDrawerPane = try #require(store.addDrawerPane(to: pane.id))

        store.removeDrawerPane(remainingDrawerPane.id, from: pane.id)

        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test

    func test_removeDrawerPane_updatesActiveIfRemoved() {
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        // Active is dp2 (last added), remove dp2
        store.removeDrawerPane(dp2.id, from: pane.id)

        #expect(drawerView(for: pane.id)?.activeChildId == dp1.id)
    }

    @Test

    func test_removeDrawerPane_lastPane_resetsDrawerToEmpty() {
        let pane = createTabbedPane()
        let dp = store.addDrawerPane(to: pane.id)!

        store.removeDrawerPane(dp.id, from: pane.id)

        // Drawer resets to empty (always present on layout panes)
        let updated = store.pane(pane.id)!
        #expect((updated.drawer) != nil)
        #expect(updated.drawer!.paneIds.isEmpty)
        #expect((drawerView(for: pane.id)?.activeChildId) == nil)
    }

    @Test

    func test_removeDrawerPane_invalidParent_noOp() {
        // Should not crash
        store.removeDrawerPane(UUID(), from: UUID())
    }

    // MARK: - toggleDrawer

    @Test

    func test_toggleDrawer_collapsesWhenExpanded() {
        let pane = createTabbedPane()
        _ = store.addDrawerPane(to: pane.id)

        store.toggleDrawer(for: pane.id)

        #expect(!(store.pane(pane.id)!.drawer!.isExpanded))
    }

    @Test

    func test_toggleDrawer_expandsWhenCollapsed() {
        let pane = createTabbedPane()
        _ = store.addDrawerPane(to: pane.id)
        store.toggleDrawer(for: pane.id)

        store.toggleDrawer(for: pane.id)

        #expect(store.pane(pane.id)!.drawer!.isExpanded)
    }

    @Test

    func test_toggleDrawer_emptyDrawer_expandsAndCollapses() {
        // Arrange
        let pane = createTabbedPane()
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
        let pane1 = createTabbedPane()
        let pane2 = createTabbedPane()
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
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        _ = store.addDrawerPane(to: pane.id)!

        store.setActiveDrawerPane(dp1.id, in: pane.id)

        #expect(drawerView(for: pane.id)?.activeChildId == dp1.id)
    }

    @Test

    func test_setActiveDrawerPane_invalidId_noOp() {
        let pane = createTabbedPane()
        let dp = store.addDrawerPane(to: pane.id)!

        store.setActiveDrawerPane(UUID(), in: pane.id)

        // Should remain unchanged
        #expect(drawerView(for: pane.id)?.activeChildId == dp.id)
    }

    // MARK: - moveDrawerPane

    @Test
    func test_moveDrawerPane_repositionsInLayoutAndFocusesMovedPane() {
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!
        let dp3 = store.addDrawerPane(to: pane.id)!

        let beforeOrder = drawerView(for: pane.id)!.layout.paneIds
        #expect(Set(beforeOrder) == Set([dp1.id, dp2.id, dp3.id]))

        store.moveDrawerPane(
            dp1.id,
            in: pane.id,
            target: .rowSlot(row: .top, insertionIndex: 3),
            sizingMode: .proportional
        )

        let drawerView = drawerView(for: pane.id)!
        let afterOrder = drawerView.layout.paneIds
        #expect(Set(afterOrder) == Set([dp1.id, dp2.id, dp3.id]))
        #expect(afterOrder.last == dp1.id)
        #expect(drawerView.activeChildId == dp1.id)
    }

    @Test
    func test_moveDrawerPane_invalidTarget_noOp() {
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!
        let beforeOrder = drawerView(for: pane.id)!.layout.paneIds

        store.moveDrawerPane(
            dp1.id,
            in: pane.id,
            target: .rowSlot(row: .bottom, insertionIndex: 0),
            sizingMode: .proportional
        )

        let drawerView = drawerView(for: pane.id)!
        #expect(drawerView.layout.paneIds == beforeOrder)
        #expect(drawerView.layout.contains(dp2.id))
    }

    // MARK: - resizeDrawerPane

    @Test

    func test_resizeDrawerPane_updatesLayout() {
        // Arrange
        let pane = createTabbedPane()
        _ = store.addDrawerPane(to: pane.id)!
        _ = store.addDrawerPane(to: pane.id)!

        let view = drawerView(for: pane.id)!
        guard let dividerId = view.layout.dividerIds.first else {
            Issue.record("Expected drawer layout divider")
            return
        }

        // Act
        store.resizeDrawerPane(parentPaneId: pane.id, splitId: dividerId, ratio: 0.7)

        // Assert
        let updated = drawerView(for: pane.id)!
        #expect(abs((updated.layout.ratioForSplit(dividerId) ?? 0) - (0.7)) <= 0.01)
    }

    @Test

    func test_equalizeDrawerPanes_resetsRatios() {
        // Arrange
        let pane = createTabbedPane()
        _ = store.addDrawerPane(to: pane.id)
        _ = store.addDrawerPane(to: pane.id)

        let view = drawerView(for: pane.id)!
        guard let dividerId = view.layout.dividerIds.first else {
            Issue.record("Expected drawer layout divider")
            return
        }
        store.resizeDrawerPane(parentPaneId: pane.id, splitId: dividerId, ratio: 0.8)

        // Act
        store.equalizeDrawerPanes(parentPaneId: pane.id)

        // Assert
        let updated = drawerView(for: pane.id)!
        #expect(abs((updated.layout.ratioForSplit(dividerId) ?? 0) - (0.5)) <= 0.01)
    }

    // MARK: - minimizeDrawerPane / expandDrawerPane

    @Test

    func test_minimizeDrawerPane_returnsTrue_onSuccess() {
        // Arrange
        let pane = createTabbedPane()
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
        let pane = createTabbedPane()
        let dp = store.addDrawerPane(to: pane.id)!

        // Act
        let result = store.minimizeDrawerPane(dp.id, in: pane.id)

        // Assert — minimizing last pane is now allowed
        #expect(result)
        #expect(drawerView(for: pane.id)?.minimizedPaneIds.contains(dp.id) == true)
        #expect((drawerView(for: pane.id)?.activeChildId) == nil)
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
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!

        // Act
        store.minimizeDrawerPane(dp1.id, in: pane.id)

        // Assert
        let drawerView = drawerView(for: pane.id)!
        #expect(drawerView.minimizedPaneIds.contains(dp1.id))
        #expect(!(drawerView.minimizedPaneIds.contains(dp2.id)))
    }

    @Test

    func test_minimizeDrawerPane_lastVisible_succeeds() {
        // Arrange — single drawer pane
        let pane = createTabbedPane()
        let dp = store.addDrawerPane(to: pane.id)!

        // Act — minimize the only pane
        store.minimizeDrawerPane(dp.id, in: pane.id)

        // Assert — minimizing last pane is now allowed
        #expect(drawerView(for: pane.id)?.minimizedPaneIds.contains(dp.id) == true)
        #expect((drawerView(for: pane.id)?.activeChildId) == nil)
    }

    @Test

    func test_minimizeDrawerPane_switchesActiveIfMinimized() {
        // Arrange
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        let dp2 = store.addDrawerPane(to: pane.id)!
        // dp2 is active (last added)

        // Act — minimize the active pane
        store.minimizeDrawerPane(dp2.id, in: pane.id)

        // Assert — active should switch to dp1
        #expect(drawerView(for: pane.id)?.activeChildId == dp1.id)
    }

    @Test

    func test_expandDrawerPane_removesFromMinimizedSet() {
        // Arrange
        let pane = createTabbedPane()
        let dp1 = store.addDrawerPane(to: pane.id)!
        _ = store.addDrawerPane(to: pane.id)
        store.minimizeDrawerPane(dp1.id, in: pane.id)
        #expect(drawerView(for: pane.id)?.minimizedPaneIds.contains(dp1.id) == true)

        // Act
        store.expandDrawerPane(dp1.id, in: pane.id)

        // Assert
        #expect(drawerView(for: pane.id)?.minimizedPaneIds.contains(dp1.id) == false)
    }

    // MARK: - Cascade Deletion

    @Test

    func test_removePane_cascadeDeletesDrawerChildren() {
        // Arrange — parent pane with 2 drawer children
        let pane = createTabbedPane()
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
    func test_removePane_cascadeDeletesDrawerChildrenFromTabMembershipAndSaves() async throws {
        let pane = createTabbedPane()
        let sibling = store.createPane()
        let tab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))
        #expect(
            store.insertPane(
                sibling.id,
                inTab: tab.id,
                at: pane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let drawerPane = try #require(store.addDrawerPane(to: pane.id))

        store.removePane(pane.id)

        let remainingTab = try #require(store.tabLayoutAtom.tabContaining(paneId: sibling.id))
        #expect(!remainingTab.allPaneIds.contains(pane.id))
        #expect(!remainingTab.allPaneIds.contains(drawerPane.id))
        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test
    func test_createArrangementAfterDrawerPane_excludesDrawerChildFromMainLayoutAndSaves() async throws {
        let pane = createTabbedPane()
        let drawerPane = try #require(store.addDrawerPane(to: pane.id))
        let tab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))

        let arrangementId = try #require(store.createArrangement(name: "Focus", inTab: tab.id))

        let updatedTab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))
        let arrangement = try #require(updatedTab.arrangements.first { $0.id == arrangementId })
        #expect(!arrangement.layout.contains(drawerPane.id))
        #expect(arrangement.drawerViews.values.contains { $0.layout.contains(drawerPane.id) })
        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test
    func test_extractDrawerOwningPane_movesDrawerChildMembershipAndSaves() async throws {
        let pane = createTabbedPane()
        let sibling = store.createPane()
        let sourceTab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))
        #expect(
            store.insertPane(
                sibling.id,
                inTab: sourceTab.id,
                at: pane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let drawerPane = try #require(store.addDrawerPane(to: pane.id))

        let extractedTab = try #require(store.extractPane(pane.id, fromTab: sourceTab.id))

        let updatedSourceTab = try #require(store.tabLayoutAtom.tabContaining(paneId: sibling.id))
        #expect(!updatedSourceTab.allPaneIds.contains(drawerPane.id))
        #expect(extractedTab.allPaneIds.contains(pane.id))
        #expect(extractedTab.allPaneIds.contains(drawerPane.id))
        #expect(
            extractedTab.arrangements.contains { arrangement in
                arrangement.drawerViews.values.contains { $0.layout.contains(drawerPane.id) }
            })
        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test
    func test_breakUpTab_movesDrawerChildrenWithParentPanesAndSaves() async throws {
        let pane = createTabbedPane()
        let sibling = store.createPane()
        let originalTab = try #require(store.tabLayoutAtom.tabContaining(paneId: pane.id))
        #expect(
            store.insertPane(
                sibling.id,
                inTab: originalTab.id,
                at: pane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let drawerPane = try #require(store.addDrawerPane(to: pane.id))

        let newTabs = store.breakUpTab(originalTab.id)

        let ownerTab = try #require(newTabs.first { $0.allPaneIds.contains(pane.id) })
        #expect(ownerTab.allPaneIds.contains(drawerPane.id))
        #expect(
            ownerTab.arrangements.contains { arrangement in
                arrangement.drawerViews.values.contains { $0.layout.contains(drawerPane.id) }
            })
        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test
    func test_mergeDrawerOwningTab_movesDrawerChildMembershipAndSaves() async throws {
        let sourceParent = createTabbedPane()
        let sourceTab = try #require(store.tabLayoutAtom.tabContaining(paneId: sourceParent.id))
        let drawerPane = try #require(store.addDrawerPane(to: sourceParent.id))
        let targetPane = createTabbedPane()
        let targetTab = try #require(store.tabLayoutAtom.tabContaining(paneId: targetPane.id))

        store.mergeTab(
            sourceId: sourceTab.id,
            intoTarget: targetTab.id,
            at: targetPane.id,
            direction: .horizontal,
            position: .after
        )

        let mergedTab = try #require(store.tabLayoutAtom.tabContaining(paneId: sourceParent.id))
        #expect(mergedTab.id == targetTab.id)
        #expect(mergedTab.allPaneIds.contains(drawerPane.id))
        #expect(
            mergedTab.arrangements.contains { arrangement in
                arrangement.drawerViews.values.contains { $0.layout.contains(drawerPane.id) }
            })
        try await saveLiveWorkspaceSnapshotToSQLite()
    }

    @Test

    func test_removeLastDrawerPane_preservesIsExpanded() {
        // Arrange — collapsed drawer with one pane
        let pane = createTabbedPane()
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
        let pane = createTabbedPane()
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
        let pane1 = createTabbedPane()
        let pane2 = createTabbedPane()
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
        let pane = createTabbedPane()
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

        let pane = store1.createPane()
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
            #expect(store2.drawerView(forParent: restored.id)?.activeChildId == dp.id)

            // Drawer child pane should also be restored in store
            let restoredDrawerPane = store2.pane(dp.id)
            #expect((restoredDrawerPane) != nil)
            #expect(restoredDrawerPane?.metadata.title == "Drawer")
            #expect(restoredDrawerPane?.isDrawerChild ?? false)
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
