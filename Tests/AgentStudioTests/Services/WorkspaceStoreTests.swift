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

    func test_setProviderHandle() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        // Act
        store.setProviderHandle(session.id, handle: "tmux-abc123")

        // Assert
        XCTAssertEqual(store.sessions[0].providerHandle, "tmux-abc123")
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
        store.save()

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
}
