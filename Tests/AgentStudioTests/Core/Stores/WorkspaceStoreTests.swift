import Foundation
// swiftlint:disable file_length type_body_length
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreTests {

    private var store: WorkspaceStore!
    private var tempDir: URL!

    init() {
        // Use a temp directory to avoid polluting real workspace data
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(persistor: persistor)
        store.restore()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
    }

    // MARK: - Init & Restore

    @Test

    func test_restore_emptyState() {
        // Assert
        #expect(store.panes.isEmpty)
        #expect(store.repos.isEmpty)
        #expect(store.tabs.isEmpty)
        #expect((store.activeTabId) == nil)
    }

    // MARK: - Pane CRUD

    @Test

    func test_createPane_addsToPanes() {
        // Act
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Test")
        )

        // Assert
        #expect(store.panes.count == 1)
        #expect((store.pane(pane.id)) != nil)
        #expect(store.pane(pane.id)?.provider == .zmx)
    }

    @Test

    func test_createPane_worktreeSource() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()

        // Act
        let pane = store.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Feature"
        )

        // Assert
        #expect(pane.worktreeId == worktreeId)
        #expect(pane.repoId == repoId)
        #expect(pane.title == "Feature")
    }

    @Test

    func test_removePane_removesFromPanes() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.removePane(pane.id)

        // Assert
        #expect(store.panes.isEmpty)
    }

    @Test

    func test_removePane_removesFromLayouts() {
        // Arrange
        let p1 = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let p2 = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)

        // Act
        store.removePane(p1.id)

        // Assert — removePane cascades to layouts and removes empty tabs
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].paneIds == [p2.id])
        #expect(store.tabs[0].activePaneId == p2.id)
    }

    @Test

    func test_removePane_lastInTab_closesTab() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        #expect(store.tabs.count == 1)

        // Act
        store.removePane(pane.id)

        // Assert
        #expect(store.tabs.isEmpty)
    }

    @Test

    func test_updatePaneTitle() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.updatePaneTitle(pane.id, title: "New Title")

        // Assert
        #expect(store.pane(pane.id)?.title == "New Title")
    }

    @Test

    func test_updatePaneCWD_updatesValue() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let cwd = URL(fileURLWithPath: "/tmp/workspace")

        // Act
        store.updatePaneCWD(pane.id, cwd: cwd)

        // Assert
        #expect(store.pane(pane.id)?.metadata.cwd == cwd)
    }

    @Test

    func test_updatePaneCWD_nilClearsValue() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        store.updatePaneCWD(pane.id, cwd: URL(fileURLWithPath: "/tmp"))

        // Act
        store.updatePaneCWD(pane.id, cwd: nil)

        // Assert
        #expect((store.pane(pane.id)?.metadata.cwd) == nil)
    }

    @Test

    func test_updatePaneCWD_sameCWD_noOpDoesNotMarkDirty() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let cwd = URL(fileURLWithPath: "/tmp")
        store.updatePaneCWD(pane.id, cwd: cwd)
        store.flush()

        // Act — update with same CWD
        store.updatePaneCWD(pane.id, cwd: cwd)

        // Assert — should not be dirty (dedup guard)
        #expect(!(store.isDirty))
    }

    @Test

    func test_updatePaneCWD_unknownPane_doesNotCrash() {
        // Act — should just log warning, not crash
        store.updatePaneCWD(UUID(), cwd: URL(fileURLWithPath: "/tmp"))

        // Assert — no crash, panes unchanged
        #expect(store.panes.isEmpty)
    }

    @Test

    func test_updatePaneAgent() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.updatePaneAgent(pane.id, agent: .claude)

        // Assert
        #expect(store.pane(pane.id)?.agent == .claude)
    }

    @Test

    func test_setResidency() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        #expect(pane.residency == .active)

        // Act
        let expiresAt = Date(timeIntervalSinceNow: 300)
        store.setResidency(.pendingUndo(expiresAt: expiresAt), for: pane.id)

        // Assert
        #expect(store.pane(pane.id)?.residency == .pendingUndo(expiresAt: expiresAt))
    }

    @Test

    func test_setResidency_backgrounded() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.setResidency(.backgrounded, for: pane.id)

        // Assert
        #expect(store.pane(pane.id)?.residency == .backgrounded)
    }

    @Test

    func test_createPane_withLifetimeAndResidency() {
        // Act
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            lifetime: .temporary,
            residency: .backgrounded
        )

        // Assert
        #expect(pane.lifetime == .temporary)
        #expect(pane.residency == .backgrounded)
    }

    // MARK: - Derived State

    @Test

    func test_isWorktreeActive_noPanes_returnsFalse() {
        #expect(!(store.isWorktreeActive(UUID())))
    }

    @Test

    func test_isWorktreeActive_withPane_returnsTrue() {
        // Arrange
        let worktreeId = UUID()
        store.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: UUID())
        )

        // Assert
        #expect(store.isWorktreeActive(worktreeId))
    }

    @Test

    func test_paneCount_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: UUID(), repoId: UUID()))

        // Assert
        #expect(store.paneCount(for: worktreeId) == 2)
    }

    // MARK: - Tab Mutations

    @Test

    func test_appendTab_addsToTabs() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(paneId: pane.id)

        // Act
        store.appendTab(tab)

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == tab.id)
    }

    @Test

    func test_removeTab_removesAndUpdatesActiveTabId() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Act
        store.removeTab(tab1.id)

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == tab2.id)
    }

    @Test

    func test_insertTab_atIndex() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s3 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        let tab3 = Tab(paneId: s3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        store.insertTab(tab3, at: 1)

        // Assert
        #expect(store.tabs.count == 3)
        #expect(store.tabs[1].id == tab3.id)
    }

    @Test

    func test_moveTab() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s3 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        let tab3 = Tab(paneId: s3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab3 to position 0
        store.moveTab(fromId: tab3.id, toIndex: 0)

        // Assert
        #expect(store.tabs[0].id == tab3.id)
        #expect(store.tabs[1].id == tab1.id)
        #expect(store.tabs[2].id == tab2.id)
    }

    // MARK: - Layout Mutations

    @Test

    func test_insertPane_splitsLayout() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        store.insertPane(
            s2.id, inTab: tab.id, at: s1.id,
            direction: .horizontal, position: .after
        )

        // Assert
        let updatedTab = store.tabs[0]
        #expect(updatedTab.isSplit)
        #expect(updatedTab.paneIds == [s1.id, s2.id])
    }

    @Test

    func test_removePaneFromLayout_collapsesToSingle() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)

        // Act
        let tabEmpty = store.removePaneFromLayout(s1.id, inTab: tab.id)

        // Assert
        #expect(!(tabEmpty))
        let updatedTab = store.tabs[0]
        #expect(!(updatedTab.isSplit))
        #expect(updatedTab.paneIds == [s2.id])
        #expect(updatedTab.activePaneId == s2.id)
    }

    @Test

    func test_removePaneFromLayout_lastPane_returnsTrue() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act — removePaneFromLayout returns true when tab is now empty
        let tabEmpty = store.removePaneFromLayout(s1.id, inTab: tab.id)

        // Assert — returns true, but tab is NOT auto-removed (caller handles that)
        #expect(tabEmpty)
    }

    @Test

    func test_equalizePanes() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)
        store.insertPane(s2.id, inTab: tab.id, at: s1.id, direction: .horizontal, position: .after)

        // Get split ID and resize
        guard case .split(let split) = store.tabs[0].layout.root else {
            Issue.record("Expected split")
            return
        }
        store.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3)

        // Act
        store.equalizePanes(tabId: tab.id)

        // Assert
        guard case .split(let eqSplit) = store.tabs[0].layout.root else {
            Issue.record("Expected split")
            return
        }
        #expect(abs((eqSplit.ratio) - (0.5)) <= 0.001)
    }

    // MARK: - Compound Operations

    @Test

    func test_breakUpTab_splitIntoIndividual() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s3 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [s1.id, s2.id, s3.id])
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        #expect(newTabs.count == 3)
        #expect(store.tabs.count == 3)
        #expect(store.tabs[0].paneIds == [s1.id])
        #expect(store.tabs[1].paneIds == [s2.id])
        #expect(store.tabs[2].paneIds == [s3.id])
    }

    @Test

    func test_breakUpTab_singlePane_noOp() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        #expect(newTabs.isEmpty)
        #expect(store.tabs.count == 1)
    }

    @Test

    func test_extractPane() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)

        // Act
        let newTab = store.extractPane(s2.id, fromTab: tab.id)

        // Assert
        #expect((newTab) != nil)
        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].paneIds == [s1.id])
        #expect(store.tabs[1].paneIds == [s2.id])
        #expect(store.activeTabId == newTab?.id)
    }

    @Test

    func test_extractPane_singlePane_noOp() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        let result = store.extractPane(s1.id, fromTab: tab.id)

        // Assert
        #expect((result) == nil)
        #expect(store.tabs.count == 1)
    }

    @Test

    func test_mergeTab() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — merge tab2 into tab1
        store.mergeTab(
            sourceId: tab2.id, intoTarget: tab1.id,
            at: s1.id, direction: .horizontal, position: .after
        )

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].paneIds.count == 2)
        #expect(store.tabs[0].paneIds.contains(s1.id))
        #expect(store.tabs[0].paneIds.contains(s2.id))
    }

    // MARK: - Queries

    @Test

    func test_pane_byId() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Assert
        #expect(store.pane(pane.id)?.id == pane.id)
        #expect((store.pane(UUID())) == nil)
    }

    @Test

    func test_tabContaining_paneId() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Assert
        #expect(store.tabContaining(paneId: pane.id)?.id == tab.id)
        #expect((store.tabContaining(paneId: UUID())) == nil)
    }

    @Test

    func test_panes_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: UUID(), repoId: UUID()))

        // Assert
        #expect(store.panes(for: worktreeId).count == 2)
    }

    // MARK: - Persistence Round-Trip

    @Test

    func test_persistence_saveAndRestore() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            title: "Persistent"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.flush()

        // Act — create new store with same persistor
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert
        #expect(store2.panes.count == 1)
        // Find the pane by the known ID
        #expect(store2.pane(pane.id)?.title == "Persistent")
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].paneIds.count == 1)
    }

    @Test

    func test_persistence_temporaryPanesExcluded() {
        // Arrange
        let persistent = store.createPane(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            title: "Persistent",
            lifetime: .persistent
        )
        store.createPane(
            source: .floating(workingDirectory: nil, title: "Temporary"),
            title: "Temporary",
            lifetime: .temporary
        )
        let tab = Tab(paneId: persistent.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore from disk
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — only persistent pane restored
        #expect(store2.panes.count == 1)
        #expect(store2.pane(persistent.id)?.title == "Persistent")
        #expect(store2.pane(persistent.id)?.lifetime == .persistent)
    }

    // MARK: - Persistence Pruning

    @Test

    func test_persistence_temporaryPanesPrunedFromLayouts() {
        // Arrange — create a tab with both persistent and temporary panes in a split layout
        let persistent = store.createPane(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            title: "Persistent",
            lifetime: .persistent
        )
        let temporary = store.createPane(
            source: .floating(workingDirectory: nil, title: "Temporary"),
            title: "Temporary",
            lifetime: .temporary
        )
        let tab = makeTab(paneIds: [persistent.id, temporary.id])
        store.appendTab(tab)
        store.flush()

        // Act — restore from disk
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — only persistent pane remains, no dangling temporary IDs in layouts
        #expect(store2.panes.count == 1)
        #expect((store2.pane(persistent.id)) != nil)
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].paneIds == [persistent.id])
        #expect(!(store2.tabs[0].isSplit))
    }

    @Test

    func test_persistence_allTemporary_tabPruned() {
        // Arrange — tab with only temporary panes
        let temp1 = store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            lifetime: .temporary
        )
        let tab = Tab(paneId: temp1.id)
        store.appendTab(tab)
        store.flush()

        // Act
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — tab fully pruned since all panes were temporary
        #expect(store2.panes.isEmpty)
        #expect(store2.tabs.isEmpty)
    }

    @Test

    func test_persistence_activeTabIdFixupAfterPrune() {
        // Arrange — two tabs: one all-temporary (active), one persistent
        let persistent = store.createPane(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            lifetime: .persistent
        )
        let temporary = store.createPane(
            source: .floating(workingDirectory: nil, title: "Temporary"),
            lifetime: .temporary
        )
        let tab1 = Tab(paneId: persistent.id)
        let tab2 = Tab(paneId: temporary.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        // tab2 is active (appendTab sets activeTabId)
        #expect(store.activeTabId == tab2.id)
        store.flush()

        // Act — restore
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — temporary tab pruned, activeTabId points to surviving tab
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].id == tab1.id)
        #expect(store2.activeTabId == tab1.id)
    }

    // MARK: - Orphaned Pane Pruning

    @Test

    func test_restore_prunesPanesWithMissingWorktree() {
        // Arrange — add a repo with a worktree, then create a worktree-bound pane
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/orphan-test-repo"))
        let wt = makeWorktree(name: "main", path: "/tmp/orphan-test-repo", branch: "main")
        store.updateRepoWorktrees(repo.id, worktrees: [wt])

        let worktree = store.repos.first!.worktrees.first!
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Will become orphaned"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore into a new store. The persisted repo has worktrees serialized,
        // but the pane's worktreeId won't match if worktrees were deleted.
        // Simulate by restoring, then creating a pane with a fabricated worktreeId
        // that doesn't exist in any repo.
        let orphanPane = store.createPane(
            source: .worktree(worktreeId: UUID(), repoId: repo.id),
            title: "Orphaned"
        )
        let orphanTab = Tab(paneId: orphanPane.id)
        store.appendTab(orphanTab)
        store.flush()

        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — the orphaned pane (with non-existent worktreeId) is pruned;
        // the valid pane (with existing worktreeId) survives
        #expect(store2.panes.count == 1, "Only the valid pane should survive")
        #expect((store2.pane(pane.id)) != nil)
        #expect(store2.tabs.count == 1, "Only the tab with valid pane should survive")
    }

    // MARK: - Dirty Flag

    @Test

    func test_isDirty_setOnMutation_clearedOnFlush() {
        // Arrange
        #expect(!(store.isDirty))

        // Act — mutation marks dirty
        _ = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        #expect(store.isDirty)

        // Act — flush clears dirty
        store.flush()
        #expect(!(store.isDirty))
    }

    @Test

    func test_isDirty_clearedAfterDebouncedSave() async throws {
        // Arrange — mutation marks dirty
        _ = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        #expect(store.isDirty)

        // Act — wait for debounce (500ms) + margin
        try await Task.sleep(for: .milliseconds(700))

        // Assert — debounced persistNow cleared the flag
        #expect(!(store.isDirty))
    }

    // MARK: - Undo

    @Test

    func test_snapshotForClose_capturesState() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act
        let snapshot = store.snapshotForClose(tabId: tab.id)

        // Assert
        #expect((snapshot) != nil)
        #expect(snapshot?.tab.id == tab.id)
        #expect(snapshot?.panes.count == 1)
        #expect(snapshot?.tabIndex == 0)
    }

    @Test

    func test_restoreFromSnapshot_reinsertTab() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        let snapshot = store.snapshotForClose(tabId: tab.id)!

        // Act — remove tab and pane, then restore
        store.removeTab(tab.id)
        store.removePane(pane.id)
        #expect(store.tabs.isEmpty)
        #expect(store.panes.isEmpty)

        store.restoreFromSnapshot(snapshot)

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].id == tab.id)
        #expect(store.panes.count == 1)
        #expect(store.activeTabId == tab.id)
    }

    // MARK: - Worktree ID Stability

    @Test

    func test_updateRepoWorktrees_preservesExistingIds() {
        // Arrange — add repo then seed initial worktrees
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo"))
        let wt1 = makeWorktree(name: "main", path: "/tmp/wt-test-repo/main", branch: "main")
        let wt2 = makeWorktree(name: "feat", path: "/tmp/wt-test-repo/feat", branch: "feat")
        store.updateRepoWorktrees(repo.id, worktrees: [wt1, wt2])

        let storedWt1Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[0].id
        let storedWt2Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[1].id

        // Create a pane referencing wt1's ID
        let pane = store.createPane(source: .worktree(worktreeId: storedWt1Id, repoId: repo.id))

        // Act — simulate refresh with fresh Worktree instances (new UUIDs, same paths)
        let freshWt1 = makeWorktree(name: "main-updated", path: "/tmp/wt-test-repo/main", branch: "main")
        let freshWt2 = makeWorktree(name: "feat-updated", path: "/tmp/wt-test-repo/feat", branch: "feat")
        #expect(freshWt1.id != storedWt1Id, "precondition: fresh worktree has different UUID")

        store.updateRepoWorktrees(repo.id, worktrees: [freshWt1, freshWt2])

        // Assert — IDs preserved, names updated
        let updated = store.repos.first(where: { $0.id == repo.id })!
        #expect(updated.worktrees.count == 2)
        #expect(updated.worktrees[0].id == storedWt1Id, "existing worktree ID preserved")
        #expect(updated.worktrees[1].id == storedWt2Id, "existing worktree ID preserved")
        #expect(updated.worktrees[0].name == "main-updated", "name updated from discovery")
        #expect(updated.worktrees[1].name == "feat-updated", "name updated from discovery")

        // Pane still resolves
        #expect(pane.worktreeId == storedWt1Id)
        #expect((store.worktree(storedWt1Id)) != nil)
    }

    @Test

    func test_updateRepoWorktrees_addsNewWorktrees() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo2"))
        let wt1 = makeWorktree(name: "main", path: "/tmp/wt-test-repo2/main", branch: "main")
        store.updateRepoWorktrees(repo.id, worktrees: [wt1])
        let storedWt1Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[0].id

        // Act — refresh adds a new worktree
        let freshWt1 = makeWorktree(name: "main", path: "/tmp/wt-test-repo2/main", branch: "main")
        let newWt = makeWorktree(name: "hotfix", path: "/tmp/wt-test-repo2/hotfix", branch: "hotfix")
        store.updateRepoWorktrees(repo.id, worktrees: [freshWt1, newWt])

        // Assert
        let updated = store.repos.first(where: { $0.id == repo.id })!
        #expect(updated.worktrees.count == 2)
        #expect(updated.worktrees[0].id == storedWt1Id, "existing ID preserved")
        #expect(updated.worktrees[1].id == newWt.id, "new worktree gets its own ID")
    }

    @Test

    func test_updateRepoWorktrees_removesDeletedWorktrees() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo3"))
        let wt1 = makeWorktree(name: "main", path: "/tmp/wt-test-repo3/main", branch: "main")
        let wt2 = makeWorktree(name: "feat", path: "/tmp/wt-test-repo3/feat", branch: "feat")
        store.updateRepoWorktrees(repo.id, worktrees: [wt1, wt2])
        let storedWt1Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[0].id

        // Act — refresh returns only wt1 (wt2 was deleted)
        let freshWt1 = makeWorktree(name: "main", path: "/tmp/wt-test-repo3/main", branch: "main")
        store.updateRepoWorktrees(repo.id, worktrees: [freshWt1])

        // Assert — only wt1 remains
        let updated = store.repos.first(where: { $0.id == repo.id })!
        #expect(updated.worktrees.count == 1)
        #expect(updated.worktrees[0].id == storedWt1Id)
    }

    // MARK: - Restore Validation

    @Test

    func test_restore_repairsStaleActiveArrangementId() throws {
        // Arrange — persist a tab with an activeArrangementId that doesn't match any arrangement
        let pane = makePane()
        let layout = Layout(paneId: pane.id)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: UUID(),  // stale — doesn't match `arrangement.id`
            activePaneId: pane.id
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        // Assert — activeArrangementId repaired to the default arrangement
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].activeArrangementId == arrangement.id)
    }

    @Test

    func test_restore_repairsStaleActivePaneId() throws {
        // Arrange — persist a tab whose activePaneId doesn't exist in the layout
        let pane = makePane()
        let layout = Layout(paneId: pane.id)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: UUID()  // stale — not in layout
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        // Assert — activePaneId repaired to the first pane in layout
        #expect(store2.tabs[0].activePaneId == pane.id)
    }

    @Test

    func test_restore_repairsMissingDefaultArrangement() throws {
        // Arrange — construct a valid tab, then corrupt it before persisting
        let pane = makePane()
        var tab = Tab(paneId: pane.id)
        // Corrupt: clear the isDefault flag
        tab.arrangements[0].isDefault = false
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        // Assert — first arrangement promoted to default
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].arrangements[0].isDefault)
    }

    @Test

    func test_restore_syncsPanesListWithLayoutPaneIds() throws {
        // Arrange — persist a tab whose panes list drifted from layout
        let p1 = makePane()
        let p2 = makePane()
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [p1.id],  // missing p2 — drifted
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: p1.id
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [p1, p2]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        // Assert — panes list synced with layout
        #expect(Set(store2.tabs[0].panes) == Set([p1.id, p2.id]))
    }

    @Test

    func test_restore_repairsCrossTabDuplicatePanes() throws {
        // Arrange — persist two tabs sharing the same pane (corruption)
        let p1 = makePane()
        let p2 = makePane()
        let layout1 = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let layout2 = Layout(paneId: p2.id)  // p2 duplicated across tabs
        let arr1 = PaneArrangement(name: "Default", isDefault: true, layout: layout1)
        let arr2 = PaneArrangement(name: "Default", isDefault: true, layout: layout2)
        let tab1 = Tab(
            panes: [p1.id, p2.id], arrangements: [arr1],
            activeArrangementId: arr1.id, activePaneId: p1.id)
        let tab2 = Tab(
            panes: [p2.id], arrangements: [arr2],
            activeArrangementId: arr2.id, activePaneId: p2.id)
        var state = WorkspacePersistor.PersistableState()
        state.panes = [p1, p2]
        state.tabs = [tab1, tab2]
        state.activeTabId = tab1.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        // Assert — p2 should only appear in ONE tab (first wins)
        let allPanes = store2.tabs.flatMap(\.panes)
        let p2Count = allPanes.filter { $0 == p2.id }.count
        #expect(p2Count == 1, "Duplicate pane should be repaired to appear in only one tab")
    }

    @Test

    func test_restore_repairsActivePaneIdAfterDuplicateRemoval() throws {
        // Arrange — tab2's active pane is a duplicate that will be removed
        let p1 = makePane()
        let p2 = makePane()
        let layout1 = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let layout2 = Layout(paneId: p2.id)
        let arr1 = PaneArrangement(name: "Default", isDefault: true, layout: layout1)
        let arr2 = PaneArrangement(name: "Default", isDefault: true, layout: layout2)
        let tab1 = Tab(
            panes: [p1.id, p2.id], arrangements: [arr1],
            activeArrangementId: arr1.id, activePaneId: p1.id)
        let tab2 = Tab(
            panes: [p2.id], arrangements: [arr2],
            activeArrangementId: arr2.id, activePaneId: p2.id)  // active is the duplicate
        var state = WorkspacePersistor.PersistableState()
        state.panes = [p1, p2]
        state.tabs = [tab1, tab2]
        state.activeTabId = tab1.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        // Assert — if tab2 survives, its activePaneId should not be p2 (was removed)
        // Tab2 may be empty and removed, which is also a valid repair outcome
        for tab in store2.tabs {
            if let apId = tab.activePaneId {
                #expect(tab.activeArrangement.layout.paneIds.contains(apId))
            }
        }
    }

    @Test

    func test_persistence_activeTabIdNotMutatedDuringSave() {
        // Arrange — create tabs: tab1 has temporary pane (pruned on save), tab2 is persistent
        let p1 = store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            lifetime: .temporary)
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)  // select the temporary tab

        // Act — flush() calls persistNow() which prunes tab1 (all-temporary)
        // from the persisted copy. This should NOT change live activeTabId.
        _ = store.flush()

        // Assert — live activeTabId still points to tab1
        #expect(store.activeTabId == tab1.id, "flush/persistNow should not mutate live activeTabId")
    }

    // MARK: - moveTabByDelta

    @Test

    func test_moveTabByDelta_movesForward() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p3 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        let tab3 = Tab(paneId: p3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab1 forward by 2
        store.moveTabByDelta(tabId: tab1.id, delta: 2)

        // Assert — tab1 is now at index 2
        #expect(store.tabs[0].id == tab2.id)
        #expect(store.tabs[1].id == tab3.id)
        #expect(store.tabs[2].id == tab1.id)
    }

    @Test

    func test_moveTabByDelta_movesBackward() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p3 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        let tab3 = Tab(paneId: p3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab3 backward by 1
        store.moveTabByDelta(tabId: tab3.id, delta: -1)

        // Assert — tab3 is now at index 1
        #expect(store.tabs[0].id == tab1.id)
        #expect(store.tabs[1].id == tab3.id)
        #expect(store.tabs[2].id == tab2.id)
    }

    @Test

    func test_moveTabByDelta_clampsAtEnd() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — move tab1 forward by 100 (should clamp)
        store.moveTabByDelta(tabId: tab1.id, delta: 100)

        // Assert — tab1 clamped to last position
        #expect(store.tabs[0].id == tab2.id)
        #expect(store.tabs[1].id == tab1.id)
    }

    @Test

    func test_moveTabByDelta_clampsAtStart() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — move tab2 backward by 100 (should clamp to 0)
        store.moveTabByDelta(tabId: tab2.id, delta: -100)

        // Assert — tab2 clamped to first position
        #expect(store.tabs[0].id == tab2.id)
        #expect(store.tabs[1].id == tab1.id)
    }

    @Test

    func test_moveTabByDelta_singleTab_noOp() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)

        // Act — single tab, delta should be ignored
        store.moveTabByDelta(tabId: tab1.id, delta: 1)

        // Assert — unchanged
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].id == tab1.id)
    }

    // MARK: - setActiveTab

    @Test

    func test_setActiveTab_setsTabId() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        store.setActiveTab(tab2.id)

        // Assert
        #expect(store.activeTabId == tab2.id)
    }

    @Test

    func test_setActiveTab_nil_clearsActiveTab() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)
        store.setActiveTab(tab1.id)

        // Act
        store.setActiveTab(nil)

        // Assert
        #expect((store.activeTabId) == nil)
    }

    // MARK: - setActivePane

    @Test

    func test_setActivePane_validPane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)

        // Act
        store.setActivePane(p2.id, inTab: tab.id)

        // Assert
        #expect(store.tabs[0].activePaneId == p2.id)
    }

    @Test

    func test_setActivePane_invalidPane_rejected() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act — set to a pane ID that doesn't exist in the tab
        let bogus = UUID()
        store.setActivePane(bogus, inTab: tab.id)

        // Assert — unchanged
        #expect(store.tabs[0].activePaneId == p1.id)
    }

    @Test

    func test_setActivePane_nil_clearsActivePane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act
        store.setActivePane(nil, inTab: tab.id)

        // Assert
        #expect((store.tabs[0].activePaneId) == nil)
    }

    // MARK: - toggleZoom

    @Test

    func test_toggleZoom_setsZoomedPaneId() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)

        // Act — zoom in
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Assert
        #expect(store.tabs[0].zoomedPaneId == p1.id)
    }

    @Test

    func test_toggleZoom_togglesOff() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Act — toggle off
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Assert
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    @Test

    func test_toggleZoom_invalidPane_noOp() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act — zoom on a pane that isn't in the layout
        let bogus = UUID()
        store.toggleZoom(paneId: bogus, inTab: tab.id)

        // Assert — no zoom set
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - insertPane clears zoom

    @Test

    func test_insertPane_clearsZoom() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        #expect((store.tabs[0].zoomedPaneId) != nil)

        // Act — insert a new pane
        store.insertPane(p2.id, inTab: tab.id, at: p1.id, direction: .horizontal, position: .after)

        // Assert — zoom cleared
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - removePaneFromLayout clears zoom

    @Test

    func test_removePaneFromLayout_clearsZoomOnRemovedPane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        #expect(store.tabs[0].zoomedPaneId == p1.id)

        // Act — remove the zoomed pane
        store.removePaneFromLayout(p1.id, inTab: tab.id)

        // Assert — zoom cleared
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - resizePane

    @Test

    func test_resizePane_changesRatio() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        guard case .split(let splitData) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout")
            return
        }

        // Act
        store.resizePane(tabId: tab.id, splitId: splitData.id, ratio: 0.7)

        // Assert
        guard case .split(let updated) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout after resize")
            return
        }
        #expect(abs((updated.ratio) - (0.7)) <= 0.001)
    }

    // MARK: - resizePaneByDelta

    @Test

    func test_resizePaneByDelta_adjustsRatio() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        guard case .split(let before) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout")
            return
        }
        let ratioBefore = before.ratio

        // Act — resize p1 to the right (increase left pane)
        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        // Assert — ratio changed
        guard case .split(let after) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout after resize")
            return
        }
        #expect(after.ratio != ratioBefore)
    }

    @Test

    func test_resizePaneByDelta_whileZoomed_noOp() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        guard case .split(let before) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout")
            return
        }
        let ratioBefore = before.ratio

        // Act — try to resize while zoomed
        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        // Assert — ratio unchanged
        guard case .split(let after) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout")
            return
        }
        #expect(after.ratio == ratioBefore)
    }

    // MARK: - addRepo / removeRepo

    @Test

    func test_addRepo_addsToRepos() {
        // Act
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/new-repo"))

        // Assert
        #expect(store.repos.count == 1)
        #expect(store.repos[0].id == repo.id)
        #expect(store.repos[0].name == "new-repo")
    }

    @Test

    func test_addRepo_duplicate_returnsExisting() {
        // Arrange
        let path = URL(fileURLWithPath: "/tmp/dup-repo")
        let first = store.addRepo(at: path)

        // Act
        let second = store.addRepo(at: path)

        // Assert — same repo returned, not duplicated
        #expect(store.repos.count == 1)
        #expect(first.id == second.id)
    }

    @Test

    func test_removeRepo_removesFromRepos() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/del-repo"))
        #expect(store.repos.count == 1)

        // Act
        store.removeRepo(repo.id)

        // Assert
        #expect(store.repos.isEmpty)
    }

    // MARK: - setSidebarWidth / setWindowFrame

    @Test

    func test_setSidebarWidth_updatesValue() {
        // Act
        store.setSidebarWidth(300)

        // Assert
        #expect(store.sidebarWidth == 300)
    }

    @Test

    func test_setWindowFrame_updatesValue() {
        // Arrange
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

        // Act
        store.setWindowFrame(frame)

        // Assert
        #expect(store.windowFrame == frame)
    }

    @Test

    func test_setWindowFrame_nil_clearsValue() {
        // Arrange
        store.setWindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100))

        // Act
        store.setWindowFrame(nil)

        // Assert
        #expect((store.windowFrame) == nil)
    }

    // MARK: - extractPane clears zoom

    @Test

    func test_extractPane_clearsZoomOnExtractedPane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        #expect(store.tabs[0].zoomedPaneId == p1.id)

        // Act — extract the zoomed pane
        let newTab = store.extractPane(p1.id, fromTab: tab.id)

        // Assert — old tab's zoom cleared
        #expect((newTab) != nil)
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - removePaneFromLayout updates activePaneId

    @Test

    func test_removePaneFromLayout_updatesActivePaneIdWhenActiveRemoved() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)
        #expect(store.tabs[0].activePaneId == p1.id)

        // Act — remove the active pane
        store.removePaneFromLayout(p1.id, inTab: tab.id)

        // Assert — activePaneId updated to remaining pane
        #expect(store.tabs[0].activePaneId == p2.id)
    }
}
