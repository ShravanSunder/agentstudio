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

    func test_restore_createsMainView() {
        // Assert
        XCTAssertEqual(store.views.count, 1)
        XCTAssertEqual(store.views[0].kind, .main)
        XCTAssertEqual(store.activeViewId, store.views[0].id)
    }

    func test_restore_emptyState() {
        // Assert
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(store.repos.isEmpty)
        XCTAssertTrue(store.activeTabs.isEmpty)
        XCTAssertNil(store.activeTabId)
    }

    // MARK: - Session CRUD

    func test_createSession_addsToSessions() {
        // Act
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: "Test")
        )

        // Assert
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].id, session.id)
        XCTAssertEqual(session.provider, .ghostty)
    }

    func test_createSession_worktreeSource() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()

        // Act
        let session = store.createSession(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Feature"
        )

        // Assert
        XCTAssertEqual(session.worktreeId, worktreeId)
        XCTAssertEqual(session.repoId, repoId)
        XCTAssertEqual(session.title, "Feature")
    }

    func test_removeSession_removesFromSessions() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.removeSession(session.id)

        // Assert
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func test_removeSession_removesFromLayouts() {
        // Arrange
        let session1 = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let session2 = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let layout = Layout(sessionId: session1.id)
            .inserting(sessionId: session2.id, at: session1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: session1.id)
        store.appendTab(tab)

        // Act
        store.removeSession(session1.id)

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabs[0].sessionIds, [session2.id])
        XCTAssertEqual(store.activeTabs[0].activeSessionId, session2.id)
    }

    func test_removeSession_lastInTab_closesTab() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)
        XCTAssertEqual(store.activeTabs.count, 1)

        // Act
        store.removeSession(session.id)

        // Assert
        XCTAssertTrue(store.activeTabs.isEmpty)
    }

    func test_updateSessionTitle() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.updateSessionTitle(session.id, title: "New Title")

        // Assert
        XCTAssertEqual(store.sessions[0].title, "New Title")
    }

    func test_updateSessionAgent() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.updateSessionAgent(session.id, agent: .claude)

        // Assert
        XCTAssertEqual(store.sessions[0].agent, .claude)
    }

    func test_setResidency() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        XCTAssertEqual(session.residency, .active)

        // Act
        let expiresAt = Date(timeIntervalSinceNow: 300)
        store.setResidency(.pendingUndo(expiresAt: expiresAt), for: session.id)

        // Assert
        XCTAssertEqual(store.sessions[0].residency, .pendingUndo(expiresAt: expiresAt))
    }

    func test_setResidency_backgrounded() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Act
        store.setResidency(.backgrounded, for: session.id)

        // Assert
        XCTAssertEqual(store.sessions[0].residency, .backgrounded)
    }

    func test_createSession_withLifetimeAndResidency() {
        // Act
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil),
            lifetime: .temporary,
            residency: .backgrounded
        )

        // Assert
        XCTAssertEqual(session.lifetime, .temporary)
        XCTAssertEqual(session.residency, .backgrounded)
    }

    // MARK: - Derived State

    func test_isWorktreeActive_noSessions_returnsFalse() {
        XCTAssertFalse(store.isWorktreeActive(UUID()))
    }

    func test_isWorktreeActive_withSession_returnsTrue() {
        // Arrange
        let worktreeId = UUID()
        store.createSession(
            source: .worktree(worktreeId: worktreeId, repoId: UUID())
        )

        // Assert
        XCTAssertTrue(store.isWorktreeActive(worktreeId))
    }

    func test_sessionCount_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createSession(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createSession(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createSession(source: .worktree(worktreeId: UUID(), repoId: UUID()))

        // Assert
        XCTAssertEqual(store.sessionCount(for: worktreeId), 2)
    }

    // MARK: - Tab Mutations

    func test_appendTab_addsToActiveView() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(sessionId: session.id)

        // Act
        store.appendTab(tab)

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabId, tab.id)
    }

    func test_removeTab_removesAndUpdatesActiveTabId() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Act
        store.removeTab(tab1.id)

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabId, tab2.id)
    }

    func test_insertTab_atIndex() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s3 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        let tab3 = Tab(sessionId: s3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        store.insertTab(tab3, at: 1)

        // Assert
        XCTAssertEqual(store.activeTabs.count, 3)
        XCTAssertEqual(store.activeTabs[1].id, tab3.id)
    }

    func test_moveTab() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s3 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        let tab3 = Tab(sessionId: s3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab3 to position 0
        store.moveTab(fromId: tab3.id, toIndex: 0)

        // Assert
        XCTAssertEqual(store.activeTabs[0].id, tab3.id)
        XCTAssertEqual(store.activeTabs[1].id, tab1.id)
        XCTAssertEqual(store.activeTabs[2].id, tab2.id)
    }

    // MARK: - Layout Mutations

    func test_insertSession_splitsLayout() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)

        // Act
        store.insertSession(
            s2.id, inTab: tab.id, at: s1.id,
            direction: .horizontal, position: .after
        )

        // Assert
        let updatedTab = store.activeTabs[0]
        XCTAssertTrue(updatedTab.isSplit)
        XCTAssertEqual(updatedTab.sessionIds, [s1.id, s2.id])
    }

    func test_removeSessionFromLayout_collapsesToSingle() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        store.removeSessionFromLayout(s1.id, inTab: tab.id)

        // Assert
        let updatedTab = store.activeTabs[0]
        XCTAssertFalse(updatedTab.isSplit)
        XCTAssertEqual(updatedTab.sessionIds, [s2.id])
        XCTAssertEqual(updatedTab.activeSessionId, s2.id)
    }

    func test_removeSessionFromLayout_lastSession_closesTab() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)

        // Act
        store.removeSessionFromLayout(s1.id, inTab: tab.id)

        // Assert
        XCTAssertTrue(store.activeTabs.isEmpty)
    }

    func test_equalizePanes() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)
        store.insertSession(s2.id, inTab: tab.id, at: s1.id, direction: .horizontal, position: .after)

        // Get split ID and resize
        guard case .split(let split) = store.activeTabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        store.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3)

        // Act
        store.equalizePanes(tabId: tab.id)

        // Assert
        guard case .split(let eqSplit) = store.activeTabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(eqSplit.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Compound Operations

    func test_breakUpTab_splitIntoIndividual() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s3 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
            .inserting(sessionId: s3.id, at: s2.id, direction: .vertical, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        XCTAssertEqual(newTabs.count, 3)
        XCTAssertEqual(store.activeTabs.count, 3)
        XCTAssertEqual(store.activeTabs[0].sessionIds, [s1.id])
        XCTAssertEqual(store.activeTabs[1].sessionIds, [s2.id])
        XCTAssertEqual(store.activeTabs[2].sessionIds, [s3.id])
    }

    func test_breakUpTab_singleSession_noOp() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        XCTAssertTrue(newTabs.isEmpty)
        XCTAssertEqual(store.activeTabs.count, 1)
    }

    func test_extractSession() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        let newTab = store.extractSession(s2.id, fromTab: tab.id)

        // Assert
        XCTAssertNotNil(newTab)
        XCTAssertEqual(store.activeTabs.count, 2)
        XCTAssertEqual(store.activeTabs[0].sessionIds, [s1.id])
        XCTAssertEqual(store.activeTabs[1].sessionIds, [s2.id])
        XCTAssertEqual(store.activeTabId, newTab?.id)
    }

    func test_extractSession_singleSession_noOp() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)

        // Act
        let result = store.extractSession(s1.id, fromTab: tab.id)

        // Assert
        XCTAssertNil(result)
        XCTAssertEqual(store.activeTabs.count, 1)
    }

    func test_mergeTab() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — merge tab2 into tab1
        store.mergeTab(
            sourceId: tab2.id, intoTarget: tab1.id,
            at: s1.id, direction: .horizontal, position: .after
        )

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabs[0].sessionIds.count, 2)
        XCTAssertTrue(store.activeTabs[0].sessionIds.contains(s1.id))
        XCTAssertTrue(store.activeTabs[0].sessionIds.contains(s2.id))
    }

    // MARK: - View Mutations

    func test_createView() {
        // Act
        let view = store.createView(name: "Dev", kind: .saved)

        // Assert
        XCTAssertEqual(store.views.count, 2) // main + new
        XCTAssertEqual(store.views.last?.id, view.id)
        XCTAssertEqual(view.kind, .saved)
    }

    func test_switchView() {
        // Arrange
        let newView = store.createView(name: "Dev", kind: .saved)

        // Act
        store.switchView(newView.id)

        // Assert
        XCTAssertEqual(store.activeViewId, newView.id)
    }

    func test_deleteView_cannotDeleteMain() {
        // Arrange
        let mainViewId = store.views.first(where: { $0.kind == .main })!.id

        // Act
        store.deleteView(mainViewId)

        // Assert
        XCTAssertEqual(store.views.count, 1)
        XCTAssertEqual(store.views[0].kind, .main)
    }

    func test_deleteView_removesNonMain() {
        // Arrange
        let savedView = store.createView(name: "Saved", kind: .saved)

        // Act
        store.deleteView(savedView.id)

        // Assert
        XCTAssertEqual(store.views.count, 1)
        XCTAssertEqual(store.views[0].kind, .main)
    }

    func test_deleteView_switchesToMainWhenActiveDeleted() {
        // Arrange
        let savedView = store.createView(name: "Saved", kind: .saved)
        store.switchView(savedView.id)

        // Act
        store.deleteView(savedView.id)

        // Assert
        XCTAssertEqual(store.activeViewId, store.views.first(where: { $0.kind == .main })?.id)
    }

    func test_saveCurrentViewAs() {
        // Arrange
        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)

        // Act
        let saved = store.saveCurrentViewAs(name: "My Layout")

        // Assert
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.kind, .saved)
        XCTAssertEqual(saved?.name, "My Layout")
        XCTAssertEqual(saved?.tabs.count, 1)
        XCTAssertEqual(store.views.count, 2)
    }

    // MARK: - Queries

    func test_session_byId() {
        // Arrange
        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))

        // Assert
        XCTAssertEqual(store.session(session.id)?.id, session.id)
        XCTAssertNil(store.session(UUID()))
    }

    func test_tabContaining_sessionId() {
        // Arrange
        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)

        // Assert
        XCTAssertEqual(store.tabContaining(sessionId: session.id)?.id, tab.id)
        XCTAssertNil(store.tabContaining(sessionId: UUID()))
    }

    func test_sessions_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createSession(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createSession(source: .worktree(worktreeId: worktreeId, repoId: repoId))
        store.createSession(source: .worktree(worktreeId: UUID(), repoId: UUID()))

        // Assert
        XCTAssertEqual(store.sessions(for: worktreeId).count, 2)
    }

    // MARK: - Persistence Round-Trip

    func test_persistence_saveAndRestore() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            title: "Persistent"
        )
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)
        store.flush()

        // Act — create new store with same persistor
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert
        XCTAssertEqual(store2.sessions.count, 1)
        XCTAssertEqual(store2.sessions[0].title, "Persistent")
        XCTAssertEqual(store2.activeTabs.count, 1)
        XCTAssertEqual(store2.activeTabs[0].sessionIds.count, 1)
    }

    func test_persistence_temporarySessionsExcluded() {
        // Arrange
        let persistent = store.createSession(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            title: "Persistent",
            lifetime: .persistent
        )
        store.createSession(
            source: .floating(workingDirectory: nil, title: "Temporary"),
            title: "Temporary",
            lifetime: .temporary
        )
        let tab = Tab(sessionId: persistent.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore from disk
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — only persistent session restored
        XCTAssertEqual(store2.sessions.count, 1)
        XCTAssertEqual(store2.sessions[0].title, "Persistent")
        XCTAssertEqual(store2.sessions[0].lifetime, .persistent)
    }

    // MARK: - Persistence Pruning

    func test_persistence_temporarySessionsPrunedFromLayouts() {
        // Arrange — create a tab with both persistent and temporary sessions in a split layout
        let persistent = store.createSession(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            title: "Persistent",
            lifetime: .persistent
        )
        let temporary = store.createSession(
            source: .floating(workingDirectory: nil, title: "Temporary"),
            title: "Temporary",
            lifetime: .temporary
        )
        let layout = Layout(sessionId: persistent.id)
            .inserting(sessionId: temporary.id, at: persistent.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: persistent.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore from disk
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — only persistent session remains, no dangling temporary IDs in layouts
        XCTAssertEqual(store2.sessions.count, 1)
        XCTAssertEqual(store2.sessions[0].id, persistent.id)
        XCTAssertEqual(store2.activeTabs.count, 1)
        XCTAssertEqual(store2.activeTabs[0].sessionIds, [persistent.id])
        XCTAssertFalse(store2.activeTabs[0].isSplit)
    }

    func test_persistence_allTemporary_tabPruned() {
        // Arrange — tab with only temporary sessions
        let temp1 = store.createSession(
            source: .floating(workingDirectory: nil, title: nil),
            lifetime: .temporary
        )
        let tab = Tab(sessionId: temp1.id)
        store.appendTab(tab)
        store.flush()

        // Act
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — tab fully pruned since all sessions were temporary
        XCTAssertTrue(store2.sessions.isEmpty)
        XCTAssertTrue(store2.activeTabs.isEmpty)
    }

    func test_persistence_multiViewPruning() {
        // Arrange — main view + saved view, each with a temporary session
        let persistent1 = store.createSession(
            source: .floating(workingDirectory: nil, title: "P1"),
            lifetime: .persistent
        )
        let temporary1 = store.createSession(
            source: .floating(workingDirectory: nil, title: "T1"),
            lifetime: .temporary
        )
        // Main view tab with split: persistent + temporary
        let layout1 = Layout(sessionId: persistent1.id)
            .inserting(sessionId: temporary1.id, at: persistent1.id, direction: .horizontal, position: .after)
        let tab1 = Tab(layout: layout1, activeSessionId: persistent1.id)
        store.appendTab(tab1)

        // Create saved view with its own temporary session
        let savedView = store.createView(name: "Saved", kind: .saved)
        let persistent2 = store.createSession(
            source: .floating(workingDirectory: nil, title: "P2"),
            lifetime: .persistent
        )
        let temporary2 = store.createSession(
            source: .floating(workingDirectory: nil, title: "T2"),
            lifetime: .temporary
        )
        let layout2 = Layout(sessionId: persistent2.id)
            .inserting(sessionId: temporary2.id, at: persistent2.id, direction: .vertical, position: .after)
        let tab2 = Tab(layout: layout2, activeSessionId: persistent2.id)
        // Switch to saved view to add tab there
        store.switchView(savedView.id)
        store.appendTab(tab2)

        store.flush()

        // Act — restore
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — both views have temporary sessions pruned
        let mainView = store2.views.first { $0.kind == .main }!
        let savedView2 = store2.views.first { $0.kind == .saved }!

        // Main view: only persistent1 remains
        XCTAssertEqual(mainView.tabs.count, 1)
        XCTAssertEqual(mainView.tabs[0].sessionIds, [persistent1.id])
        XCTAssertFalse(mainView.tabs[0].isSplit)

        // Saved view: only persistent2 remains
        XCTAssertEqual(savedView2.tabs.count, 1)
        XCTAssertEqual(savedView2.tabs[0].sessionIds, [persistent2.id])
        XCTAssertFalse(savedView2.tabs[0].isSplit)
    }

    func test_persistence_activeTabIdFixupAfterPrune() {
        // Arrange — two tabs: one all-temporary (active), one persistent
        let persistent = store.createSession(
            source: .floating(workingDirectory: nil, title: "Persistent"),
            lifetime: .persistent
        )
        let temporary = store.createSession(
            source: .floating(workingDirectory: nil, title: "Temporary"),
            lifetime: .temporary
        )
        let tab1 = Tab(sessionId: persistent.id)
        let tab2 = Tab(sessionId: temporary.id)
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
        XCTAssertEqual(store2.activeTabs.count, 1)
        XCTAssertEqual(store2.activeTabs[0].id, tab1.id)
        XCTAssertEqual(store2.activeTabId, tab1.id)
    }

    // MARK: - Orphaned Session Pruning

    func test_restore_prunesSessionsWithMissingWorktree() {
        // Arrange — add a repo with a worktree, then create a worktree-bound session
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/orphan-test-repo"))
        let wt = makeWorktree(name: "main", path: "/tmp/orphan-test-repo", branch: "main")
        store.updateRepoWorktrees(repo.id, worktrees: [wt])

        let worktree = store.repos.first!.worktrees.first!
        let session = store.createSession(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Will become orphaned"
        )
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore into a new store. The persisted repo has worktrees serialized,
        // but the session's worktreeId won't match if worktrees were deleted.
        // Simulate by restoring, then clearing worktrees, then checking prune logic.
        // Actually: worktrees ARE persisted with repos. So the session won't be orphaned
        // unless the worktree is actually removed. Test the prune path by creating a
        // session with a fabricated worktreeId that doesn't exist in any repo.
        let orphanSession = store.createSession(
            source: .worktree(worktreeId: UUID(), repoId: repo.id),
            title: "Orphaned"
        )
        let orphanTab = Tab(sessionId: orphanSession.id)
        store.appendTab(orphanTab)
        store.flush()

        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(persistor: persistor2)
        store2.restore()

        // Assert — the orphaned session (with non-existent worktreeId) is pruned;
        // the valid session (with existing worktreeId) survives
        XCTAssertEqual(store2.sessions.count, 1, "Only the valid session should survive")
        XCTAssertEqual(store2.sessions[0].id, session.id)
        XCTAssertEqual(store2.activeTabs.count, 1, "Only the tab with valid session should survive")
    }

    // MARK: - Dirty Flag

    func test_isDirty_setOnMutation_clearedOnFlush() {
        // Arrange
        XCTAssertFalse(store.isDirty)

        // Act — mutation marks dirty
        _ = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        XCTAssertTrue(store.isDirty)

        // Act — flush clears dirty
        store.flush()
        XCTAssertFalse(store.isDirty)
    }

    func test_isDirty_clearedAfterDebouncedSave() async throws {
        // Arrange — mutation marks dirty
        _ = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        XCTAssertTrue(store.isDirty)

        // Act — wait for debounce (500ms) + margin
        try await Task.sleep(for: .milliseconds(700))

        // Assert — debounced persistNow cleared the flag
        XCTAssertFalse(store.isDirty)
    }

    func test_restoreFromSnapshot_crossViewFallback() {
        // Arrange — create a saved view, add a tab, snapshot it, then delete the view
        let savedView = store.createView(name: "Saved", kind: .saved)
        store.switchView(savedView.id)

        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)
        let snapshot = store.snapshotForClose(tabId: tab.id)!

        // Remove tab and session, then delete the saved view
        store.removeTab(tab.id)
        store.removeSession(session.id)
        store.switchView(store.views.first { $0.kind == .main }!.id)
        store.deleteView(savedView.id)
        XCTAssertFalse(store.views.contains { $0.id == savedView.id })

        // Act — restore snapshot; original view is gone, should fallback to active view
        store.restoreFromSnapshot(snapshot)

        // Assert — tab restored to main (active) view
        let mainView = store.views.first { $0.kind == .main }!
        XCTAssertTrue(mainView.tabs.contains { $0.id == tab.id })
        XCTAssertEqual(store.activeTabId, tab.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    // MARK: - Undo

    func test_snapshotForClose_capturesState() {
        // Arrange
        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)

        // Act
        let snapshot = store.snapshotForClose(tabId: tab.id)

        // Assert
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.tab.id, tab.id)
        XCTAssertEqual(snapshot?.sessions.count, 1)
        XCTAssertEqual(snapshot?.tabIndex, 0)
    }

    func test_restoreFromSnapshot_reinsertTab() {
        // Arrange
        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)
        let snapshot = store.snapshotForClose(tabId: tab.id)!

        // Act — remove tab, then restore
        store.removeTab(tab.id)
        store.removeSession(session.id)
        XCTAssertTrue(store.activeTabs.isEmpty)
        XCTAssertTrue(store.sessions.isEmpty)

        store.restoreFromSnapshot(snapshot)

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabs[0].id, tab.id)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeTabId, tab.id)
    }

    // MARK: - Invariants

    func test_mainView_alwaysExists() {
        // The main view cannot be deleted
        let mainId = store.views.first(where: { $0.kind == .main })!.id
        store.deleteView(mainId)

        // Assert — main view still exists
        XCTAssertTrue(store.views.contains(where: { $0.kind == .main }))
    }

    func test_activeViewId_alwaysValid() {
        // After restore, activeViewId points to an existing view
        XCTAssertNotNil(store.activeViewId)
        XCTAssertNotNil(store.activeView)
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

        // Create a session referencing wt1's ID
        let session = store.createSession(source: .worktree(worktreeId: storedWt1Id, repoId: repo.id))

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

        // Session still resolves
        XCTAssertEqual(session.worktreeId, storedWt1Id)
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
}
