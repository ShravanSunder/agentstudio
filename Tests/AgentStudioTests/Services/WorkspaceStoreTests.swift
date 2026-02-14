import XCTest
@testable import AgentStudio

@MainActor
final class WorkspaceStoreTests: XCTestCase {

    private var store: WorkspaceStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        // Use a temp directory to avoid polluting real workspace data
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(persistor: persistor)
        store.restore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
        super.tearDown()
    }

    // MARK: - Init & Restore

    func test_restore_emptyState() {
        // Assert
        XCTAssertTrue(store.panes.isEmpty)
        XCTAssertTrue(store.repos.isEmpty)
        XCTAssertTrue(store.tabs.isEmpty)
        XCTAssertNil(store.activeTabId)
    }

    // MARK: - Pane CRUD

    func test_createPane_addsToPanes() {
        // Act
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Test")
        )

        // Assert
        XCTAssertEqual(store.panes.count, 1)
        XCTAssertNotNil(store.pane(pane.id))
        XCTAssertEqual(store.pane(pane.id)?.provider, .ghostty)
    }

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
        XCTAssertEqual(pane.worktreeId, worktreeId)
        XCTAssertEqual(pane.repoId, repoId)
        XCTAssertEqual(pane.title, "Feature")
    }

    func test_removePane_removesFromPanes() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.removePane(pane.id)

        // Assert
        XCTAssertTrue(store.panes.isEmpty)
    }

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
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs[0].paneIds, [p2.id])
        XCTAssertEqual(store.tabs[0].activePaneId, p2.id)
    }

    func test_removePane_lastInTab_closesTab() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        XCTAssertEqual(store.tabs.count, 1)

        // Act
        store.removePane(pane.id)

        // Assert
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func test_updatePaneTitle() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.updatePaneTitle(pane.id, title: "New Title")

        // Assert
        XCTAssertEqual(store.pane(pane.id)?.title, "New Title")
    }

    func test_updatePaneCWD_updatesValue() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let cwd = URL(fileURLWithPath: "/tmp/workspace")

        // Act
        store.updatePaneCWD(pane.id, cwd: cwd)

        // Assert
        XCTAssertEqual(store.pane(pane.id)?.metadata.cwd, cwd)
    }

    func test_updatePaneCWD_nilClearsValue() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        store.updatePaneCWD(pane.id, cwd: URL(fileURLWithPath: "/tmp"))

        // Act
        store.updatePaneCWD(pane.id, cwd: nil)

        // Assert
        XCTAssertNil(store.pane(pane.id)?.metadata.cwd)
    }

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
        XCTAssertFalse(store.isDirty)
    }

    func test_updatePaneCWD_unknownPane_doesNotCrash() {
        // Act — should just log warning, not crash
        store.updatePaneCWD(UUID(), cwd: URL(fileURLWithPath: "/tmp"))

        // Assert — no crash, panes unchanged
        XCTAssertTrue(store.panes.isEmpty)
    }

    func test_updatePaneAgent() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.updatePaneAgent(pane.id, agent: .claude)

        // Assert
        XCTAssertEqual(store.pane(pane.id)?.agent, .claude)
    }

    func test_setResidency() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        XCTAssertEqual(pane.residency, .active)

        // Act
        let expiresAt = Date(timeIntervalSinceNow: 300)
        store.setResidency(.pendingUndo(expiresAt: expiresAt), for: pane.id)

        // Assert
        XCTAssertEqual(store.pane(pane.id)?.residency, .pendingUndo(expiresAt: expiresAt))
    }

    func test_setResidency_backgrounded() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.setResidency(.backgrounded, for: pane.id)

        // Assert
        XCTAssertEqual(store.pane(pane.id)?.residency, .backgrounded)
    }

    func test_createPane_withLifetimeAndResidency() {
        // Act
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            lifetime: .temporary,
            residency: .backgrounded
        )

        // Assert
        XCTAssertEqual(pane.lifetime, .temporary)
        XCTAssertEqual(pane.residency, .backgrounded)
    }

    // MARK: - Derived State

    func test_isWorktreeActive_noPanes_returnsFalse() {
        XCTAssertFalse(store.isWorktreeActive(UUID()))
    }

    func test_isWorktreeActive_withPane_returnsTrue() {
        // Arrange
        let worktreeId = UUID()
        store.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: UUID())
        )

        // Assert
        XCTAssertTrue(store.isWorktreeActive(worktreeId))
    }

    func test_paneCount_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: UUID(), repoId: UUID()))

        // Assert
        XCTAssertEqual(store.paneCount(for: worktreeId), 2)
    }

    // MARK: - Tab Mutations

    func test_appendTab_addsToTabs() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(paneId: pane.id)

        // Act
        store.appendTab(tab)

        // Assert
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabId, tab.id)
    }

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
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabId, tab2.id)
    }

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
        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.tabs[1].id, tab3.id)
    }

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
        XCTAssertEqual(store.tabs[0].id, tab3.id)
        XCTAssertEqual(store.tabs[1].id, tab1.id)
        XCTAssertEqual(store.tabs[2].id, tab2.id)
    }

    // MARK: - Layout Mutations

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
        XCTAssertTrue(updatedTab.isSplit)
        XCTAssertEqual(updatedTab.paneIds, [s1.id, s2.id])
    }

    func test_removePaneFromLayout_collapsesToSingle() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)

        // Act
        let tabEmpty = store.removePaneFromLayout(s1.id, inTab: tab.id)

        // Assert
        XCTAssertFalse(tabEmpty)
        let updatedTab = store.tabs[0]
        XCTAssertFalse(updatedTab.isSplit)
        XCTAssertEqual(updatedTab.paneIds, [s2.id])
        XCTAssertEqual(updatedTab.activePaneId, s2.id)
    }

    func test_removePaneFromLayout_lastPane_returnsTrue() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act — removePaneFromLayout returns true when tab is now empty
        let tabEmpty = store.removePaneFromLayout(s1.id, inTab: tab.id)

        // Assert — returns true, but tab is NOT auto-removed (caller handles that)
        XCTAssertTrue(tabEmpty)
    }

    func test_equalizePanes() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)
        store.insertPane(s2.id, inTab: tab.id, at: s1.id, direction: .horizontal, position: .after)

        // Get split ID and resize
        guard case .split(let split) = store.tabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        store.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3)

        // Act
        store.equalizePanes(tabId: tab.id)

        // Assert
        guard case .split(let eqSplit) = store.tabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(eqSplit.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Compound Operations

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
        XCTAssertEqual(newTabs.count, 3)
        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.tabs[0].paneIds, [s1.id])
        XCTAssertEqual(store.tabs[1].paneIds, [s2.id])
        XCTAssertEqual(store.tabs[2].paneIds, [s3.id])
    }

    func test_breakUpTab_singlePane_noOp() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        XCTAssertTrue(newTabs.isEmpty)
        XCTAssertEqual(store.tabs.count, 1)
    }

    func test_extractPane() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)

        // Act
        let newTab = store.extractPane(s2.id, fromTab: tab.id)

        // Assert
        XCTAssertNotNil(newTab)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs[0].paneIds, [s1.id])
        XCTAssertEqual(store.tabs[1].paneIds, [s2.id])
        XCTAssertEqual(store.activeTabId, newTab?.id)
    }

    func test_extractPane_singlePane_noOp() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        let result = store.extractPane(s1.id, fromTab: tab.id)

        // Assert
        XCTAssertNil(result)
        XCTAssertEqual(store.tabs.count, 1)
    }

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
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs[0].paneIds.count, 2)
        XCTAssertTrue(store.tabs[0].paneIds.contains(s1.id))
        XCTAssertTrue(store.tabs[0].paneIds.contains(s2.id))
    }

    // MARK: - Queries

    func test_pane_byId() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Assert
        XCTAssertEqual(store.pane(pane.id)?.id, pane.id)
        XCTAssertNil(store.pane(UUID()))
    }

    func test_tabContaining_paneId() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Assert
        XCTAssertEqual(store.tabContaining(paneId: pane.id)?.id, tab.id)
        XCTAssertNil(store.tabContaining(paneId: UUID()))
    }

    func test_panes_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createPane(source: .worktree(worktreeId: UUID(), repoId: UUID()))

        // Assert
        XCTAssertEqual(store.panes(for: worktreeId).count, 2)
    }

    // MARK: - Persistence Round-Trip

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
        XCTAssertEqual(store2.panes.count, 1)
        // Find the pane by the known ID
        XCTAssertEqual(store2.pane(pane.id)?.title, "Persistent")
        XCTAssertEqual(store2.tabs.count, 1)
        XCTAssertEqual(store2.tabs[0].paneIds.count, 1)
    }

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
        XCTAssertEqual(store2.panes.count, 1)
        XCTAssertEqual(store2.pane(persistent.id)?.title, "Persistent")
        XCTAssertEqual(store2.pane(persistent.id)?.lifetime, .persistent)
    }

    // MARK: - Persistence Pruning

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
        XCTAssertEqual(store2.panes.count, 1)
        XCTAssertNotNil(store2.pane(persistent.id))
        XCTAssertEqual(store2.tabs.count, 1)
        XCTAssertEqual(store2.tabs[0].paneIds, [persistent.id])
        XCTAssertFalse(store2.tabs[0].isSplit)
    }

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
        XCTAssertTrue(store2.panes.isEmpty)
        XCTAssertTrue(store2.tabs.isEmpty)
    }

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
        XCTAssertEqual(store.activeTabId, tab2.id)
        store.flush()

        // Act — restore
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — temporary tab pruned, activeTabId points to surviving tab
        XCTAssertEqual(store2.tabs.count, 1)
        XCTAssertEqual(store2.tabs[0].id, tab1.id)
        XCTAssertEqual(store2.activeTabId, tab1.id)
    }

    // MARK: - Orphaned Pane Pruning

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
        XCTAssertEqual(store2.panes.count, 1, "Only the valid pane should survive")
        XCTAssertNotNil(store2.pane(pane.id))
        XCTAssertEqual(store2.tabs.count, 1, "Only the tab with valid pane should survive")
    }

    // MARK: - Dirty Flag

    func test_isDirty_setOnMutation_clearedOnFlush() {
        // Arrange
        XCTAssertFalse(store.isDirty)

        // Act — mutation marks dirty
        _ = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        XCTAssertTrue(store.isDirty)

        // Act — flush clears dirty
        store.flush()
        XCTAssertFalse(store.isDirty)
    }

    func test_isDirty_clearedAfterDebouncedSave() async throws {
        // Arrange — mutation marks dirty
        _ = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        XCTAssertTrue(store.isDirty)

        // Act — wait for debounce (500ms) + margin
        try await Task.sleep(for: .milliseconds(700))

        // Assert — debounced persistNow cleared the flag
        XCTAssertFalse(store.isDirty)
    }

    // MARK: - Undo

    func test_snapshotForClose_capturesState() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act
        let snapshot = store.snapshotForClose(tabId: tab.id)

        // Assert
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.tab.id, tab.id)
        XCTAssertEqual(snapshot?.panes.count, 1)
        XCTAssertEqual(snapshot?.tabIndex, 0)
    }

    func test_restoreFromSnapshot_reinsertTab() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        let snapshot = store.snapshotForClose(tabId: tab.id)!

        // Act — remove tab and pane, then restore
        store.removeTab(tab.id)
        store.removePane(pane.id)
        XCTAssertTrue(store.tabs.isEmpty)
        XCTAssertTrue(store.panes.isEmpty)

        store.restoreFromSnapshot(snapshot)

        // Assert
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs[0].id, tab.id)
        XCTAssertEqual(store.panes.count, 1)
        XCTAssertEqual(store.activeTabId, tab.id)
    }

    // MARK: - Worktree ID Stability

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
        XCTAssertNotEqual(freshWt1.id, storedWt1Id, "precondition: fresh worktree has different UUID")

        store.updateRepoWorktrees(repo.id, worktrees: [freshWt1, freshWt2])

        // Assert — IDs preserved, names updated
        let updated = store.repos.first(where: { $0.id == repo.id })!
        XCTAssertEqual(updated.worktrees.count, 2)
        XCTAssertEqual(updated.worktrees[0].id, storedWt1Id, "existing worktree ID preserved")
        XCTAssertEqual(updated.worktrees[1].id, storedWt2Id, "existing worktree ID preserved")
        XCTAssertEqual(updated.worktrees[0].name, "main-updated", "name updated from discovery")
        XCTAssertEqual(updated.worktrees[1].name, "feat-updated", "name updated from discovery")

        // Pane still resolves
        XCTAssertEqual(pane.worktreeId, storedWt1Id)
        XCTAssertNotNil(store.worktree(storedWt1Id))
    }

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
        XCTAssertEqual(updated.worktrees.count, 2)
        XCTAssertEqual(updated.worktrees[0].id, storedWt1Id, "existing ID preserved")
        XCTAssertEqual(updated.worktrees[1].id, newWt.id, "new worktree gets its own ID")
    }

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
        XCTAssertEqual(updated.worktrees.count, 1)
        XCTAssertEqual(updated.worktrees[0].id, storedWt1Id)
    }

    // MARK: - Restore Validation

    func test_restore_repairsStaleActiveArrangementId() throws {
        // Arrange — persist a tab with an activeArrangementId that doesn't match any arrangement
        let pane = makePane()
        let layout = Layout(paneId: pane.id)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: UUID(), // stale — doesn't match `arrangement.id`
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
        XCTAssertEqual(store2.tabs.count, 1)
        XCTAssertEqual(store2.tabs[0].activeArrangementId, arrangement.id)
    }

    func test_restore_repairsStaleActivePaneId() throws {
        // Arrange — persist a tab whose activePaneId doesn't exist in the layout
        let pane = makePane()
        let layout = Layout(paneId: pane.id)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: UUID() // stale — not in layout
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
        XCTAssertEqual(store2.tabs[0].activePaneId, pane.id)
    }

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
        XCTAssertEqual(store2.tabs.count, 1)
        XCTAssertTrue(store2.tabs[0].arrangements[0].isDefault)
    }

    func test_restore_syncsPanesListWithLayoutPaneIds() throws {
        // Arrange — persist a tab whose panes list drifted from layout
        let p1 = makePane()
        let p2 = makePane()
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [p1.id], // missing p2 — drifted
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
        XCTAssertEqual(Set(store2.tabs[0].panes), Set([p1.id, p2.id]))
    }

    // MARK: - moveTabByDelta

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
        XCTAssertEqual(store.tabs[0].id, tab2.id)
        XCTAssertEqual(store.tabs[1].id, tab3.id)
        XCTAssertEqual(store.tabs[2].id, tab1.id)
    }

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
        XCTAssertEqual(store.tabs[0].id, tab1.id)
        XCTAssertEqual(store.tabs[1].id, tab3.id)
        XCTAssertEqual(store.tabs[2].id, tab2.id)
    }

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
        XCTAssertEqual(store.tabs[0].id, tab2.id)
        XCTAssertEqual(store.tabs[1].id, tab1.id)
    }

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
        XCTAssertEqual(store.tabs[0].id, tab2.id)
        XCTAssertEqual(store.tabs[1].id, tab1.id)
    }

    func test_moveTabByDelta_singleTab_noOp() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)

        // Act — single tab, delta should be ignored
        store.moveTabByDelta(tabId: tab1.id, delta: 1)

        // Assert — unchanged
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs[0].id, tab1.id)
    }

    // MARK: - setActiveTab

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
        XCTAssertEqual(store.activeTabId, tab2.id)
    }

    func test_setActiveTab_nil_clearsActiveTab() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)
        store.setActiveTab(tab1.id)

        // Act
        store.setActiveTab(nil)

        // Assert
        XCTAssertNil(store.activeTabId)
    }

    // MARK: - setActivePane

    func test_setActivePane_validPane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)

        // Act
        store.setActivePane(p2.id, inTab: tab.id)

        // Assert
        XCTAssertEqual(store.tabs[0].activePaneId, p2.id)
    }

    func test_setActivePane_invalidPane_rejected() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act — set to a pane ID that doesn't exist in the tab
        let bogus = UUID()
        store.setActivePane(bogus, inTab: tab.id)

        // Assert — unchanged
        XCTAssertEqual(store.tabs[0].activePaneId, p1.id)
    }

    func test_setActivePane_nil_clearsActivePane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act
        store.setActivePane(nil, inTab: tab.id)

        // Assert
        XCTAssertNil(store.tabs[0].activePaneId)
    }

    // MARK: - toggleZoom

    func test_toggleZoom_setsZoomedPaneId() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)

        // Act — zoom in
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Assert
        XCTAssertEqual(store.tabs[0].zoomedPaneId, p1.id)
    }

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
        XCTAssertNil(store.tabs[0].zoomedPaneId)
    }

    func test_toggleZoom_invalidPane_noOp() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act — zoom on a pane that isn't in the layout
        let bogus = UUID()
        store.toggleZoom(paneId: bogus, inTab: tab.id)

        // Assert — no zoom set
        XCTAssertNil(store.tabs[0].zoomedPaneId)
    }

    // MARK: - insertPane clears zoom

    func test_insertPane_clearsZoom() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        XCTAssertNotNil(store.tabs[0].zoomedPaneId)

        // Act — insert a new pane
        store.insertPane(p2.id, inTab: tab.id, at: p1.id, direction: .horizontal, position: .after)

        // Assert — zoom cleared
        XCTAssertNil(store.tabs[0].zoomedPaneId)
    }

    // MARK: - removePaneFromLayout clears zoom

    func test_removePaneFromLayout_clearsZoomOnRemovedPane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        XCTAssertEqual(store.tabs[0].zoomedPaneId, p1.id)

        // Act — remove the zoomed pane
        store.removePaneFromLayout(p1.id, inTab: tab.id)

        // Assert — zoom cleared
        XCTAssertNil(store.tabs[0].zoomedPaneId)
    }

    // MARK: - resizePane

    func test_resizePane_changesRatio() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        guard case .split(let splitData) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }

        // Act
        store.resizePane(tabId: tab.id, splitId: splitData.id, ratio: 0.7)

        // Assert
        guard case .split(let updated) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout after resize")
            return
        }
        XCTAssertEqual(updated.ratio, 0.7, accuracy: 0.001)
    }

    // MARK: - resizePaneByDelta

    func test_resizePaneByDelta_adjustsRatio() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        guard case .split(let before) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }
        let ratioBefore = before.ratio

        // Act — resize p1 to the right (increase left pane)
        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        // Assert — ratio changed
        guard case .split(let after) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout after resize")
            return
        }
        XCTAssertNotEqual(after.ratio, ratioBefore)
    }

    func test_resizePaneByDelta_whileZoomed_noOp() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        guard case .split(let before) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }
        let ratioBefore = before.ratio

        // Act — try to resize while zoomed
        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        // Assert — ratio unchanged
        guard case .split(let after) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }
        XCTAssertEqual(after.ratio, ratioBefore)
    }

    // MARK: - addRepo / removeRepo

    func test_addRepo_addsToRepos() {
        // Act
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/new-repo"))

        // Assert
        XCTAssertEqual(store.repos.count, 1)
        XCTAssertEqual(store.repos[0].id, repo.id)
        XCTAssertEqual(store.repos[0].name, "new-repo")
    }

    func test_addRepo_duplicate_returnsExisting() {
        // Arrange
        let path = URL(fileURLWithPath: "/tmp/dup-repo")
        let first = store.addRepo(at: path)

        // Act
        let second = store.addRepo(at: path)

        // Assert — same repo returned, not duplicated
        XCTAssertEqual(store.repos.count, 1)
        XCTAssertEqual(first.id, second.id)
    }

    func test_removeRepo_removesFromRepos() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/del-repo"))
        XCTAssertEqual(store.repos.count, 1)

        // Act
        store.removeRepo(repo.id)

        // Assert
        XCTAssertTrue(store.repos.isEmpty)
    }

    // MARK: - setSidebarWidth / setWindowFrame

    func test_setSidebarWidth_updatesValue() {
        // Act
        store.setSidebarWidth(300)

        // Assert
        XCTAssertEqual(store.sidebarWidth, 300)
    }

    func test_setWindowFrame_updatesValue() {
        // Arrange
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

        // Act
        store.setWindowFrame(frame)

        // Assert
        XCTAssertEqual(store.windowFrame, frame)
    }

    func test_setWindowFrame_nil_clearsValue() {
        // Arrange
        store.setWindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100))

        // Act
        store.setWindowFrame(nil)

        // Assert
        XCTAssertNil(store.windowFrame)
    }

    // MARK: - extractPane clears zoom

    func test_extractPane_clearsZoomOnExtractedPane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        XCTAssertEqual(store.tabs[0].zoomedPaneId, p1.id)

        // Act — extract the zoomed pane
        let newTab = store.extractPane(p1.id, fromTab: tab.id)

        // Assert — old tab's zoom cleared
        XCTAssertNotNil(newTab)
        XCTAssertNil(store.tabs[0].zoomedPaneId)
    }

    // MARK: - removePaneFromLayout updates activePaneId

    func test_removePaneFromLayout_updatesActivePaneIdWhenActiveRemoved() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)
        XCTAssertEqual(store.tabs[0].activePaneId, p1.id)

        // Act — remove the active pane
        store.removePaneFromLayout(p1.id, inTab: tab.id)

        // Assert — activePaneId updated to remaining pane
        XCTAssertEqual(store.tabs[0].activePaneId, p2.id)
    }
}
