import XCTest
@testable import AgentStudio

@MainActor
final class ActionExecutorTests: XCTestCase {

    private var store: WorkspaceStore!
    private var viewRegistry: ViewRegistry!
    private var coordinator: TerminalViewCoordinator!
    private var runtime: SessionRuntime!
    private var executor: ActionExecutor!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "executor-tests-\(UUID().uuidString)")
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

    // MARK: - Execute: selectTab

    func test_execute_selectTab_setsActiveTab() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Act
        executor.execute(.selectTab(tabId: tab2.id))

        // Assert
        XCTAssertEqual(store.activeTabId, tab2.id)
    }

    // MARK: - Execute: closeTab

    func test_execute_closeTab_removesTab() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)
        XCTAssertEqual(store.activeTabs.count, 1)

        // Act
        executor.execute(.closeTab(tabId: tab.id))

        // Assert
        XCTAssertTrue(store.activeTabs.isEmpty)
    }

    func test_execute_closeTab_pushesToUndoStack() {
        // Arrange
        let session = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)

        // Act
        executor.execute(.closeTab(tabId: tab.id))

        // Assert
        XCTAssertEqual(executor.undoStack.count, 1)
        XCTAssertEqual(executor.undoStack[0].tab.id, tab.id)
    }

    func test_execute_closeTab_multipleCloses_stacksUndo() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(.closeTab(tabId: tab1.id))
        executor.execute(.closeTab(tabId: tab2.id))

        // Assert
        XCTAssertEqual(executor.undoStack.count, 2)
        XCTAssertEqual(executor.undoStack[0].tab.id, tab1.id)
        XCTAssertEqual(executor.undoStack[1].tab.id, tab2.id)
    }

    // MARK: - Undo Close Tab

    func test_undoCloseTab_restoresTab() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: "Undoable")
        )
        let tab = Tab(sessionId: session.id)
        store.appendTab(tab)
        executor.execute(.closeTab(tabId: tab.id))
        XCTAssertTrue(store.activeTabs.isEmpty)

        // Act
        executor.undoCloseTab()

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabs[0].id, tab.id)
        XCTAssertTrue(executor.undoStack.isEmpty)
    }

    func test_undoCloseTab_emptyStack_noOp() {
        // Act — should not crash
        executor.undoCloseTab()

        // Assert
        XCTAssertTrue(executor.undoStack.isEmpty)
    }

    // MARK: - Execute: breakUpTab

    func test_execute_breakUpTab_splitsIntoIndividualTabs() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        executor.execute(.breakUpTab(tabId: tab.id))

        // Assert
        XCTAssertEqual(store.activeTabs.count, 2)
        XCTAssertEqual(store.activeTabs[0].sessionIds, [s1.id])
        XCTAssertEqual(store.activeTabs[1].sessionIds, [s2.id])
    }

    // MARK: - Execute: extractPaneToTab

    func test_execute_extractPaneToTab_createsNewTab() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        executor.execute(.extractPaneToTab(tabId: tab.id, paneId: s2.id))

        // Assert
        XCTAssertEqual(store.activeTabs.count, 2)
    }

    // MARK: - Execute: focusPane

    func test_execute_focusPane_setsActiveSession() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        executor.execute(.focusPane(tabId: tab.id, paneId: s2.id))

        // Assert
        XCTAssertEqual(store.activeTabs[0].activeSessionId, s2.id)
    }

    // MARK: - Execute: resizePane

    func test_execute_resizePane_updatesRatio() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)
        store.insertSession(
            s2.id, inTab: tab.id, at: s1.id,
            direction: .horizontal, position: .after
        )

        // Get split ID
        guard case .split(let split) = store.activeTabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }

        // Act
        executor.execute(.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3))

        // Assert
        guard case .split(let updatedSplit) = store.activeTabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }
        XCTAssertEqual(updatedSplit.ratio, 0.3, accuracy: 0.001)
    }

    // MARK: - Execute: equalizePanes

    func test_execute_equalizePanes_resetsRatios() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(sessionId: s1.id)
        store.appendTab(tab)
        store.insertSession(
            s2.id, inTab: tab.id, at: s1.id,
            direction: .horizontal, position: .after
        )

        // Resize first
        guard case .split(let split) = store.activeTabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        store.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3)

        // Act
        executor.execute(.equalizePanes(tabId: tab.id))

        // Assert
        guard case .split(let eqSplit) = store.activeTabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(eqSplit.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Execute: closePane

    func test_execute_closePane_removesFromLayout() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
        store.appendTab(tab)

        // Act
        executor.execute(.closePane(tabId: tab.id, paneId: s1.id))

        // Assert
        XCTAssertEqual(store.activeTabs[0].sessionIds, [s2.id])
        XCTAssertFalse(store.activeTabs[0].isSplit)
    }

    // MARK: - Execute: insertPane (existingPane)

    func test_execute_insertPane_existingPane_movesSession() {
        // Arrange — s2 in tab2, move to tab1 next to s1
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(.insertPane(
            source: .existingPane(paneId: s2.id, sourceTabId: tab2.id),
            targetTabId: tab1.id,
            targetPaneId: s1.id,
            direction: .right
        ))

        // Assert — tab2 was removed (last session extracted), tab1 now has split
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertTrue(store.activeTabs[0].isSplit)
        XCTAssertTrue(store.activeTabs[0].sessionIds.contains(s1.id))
        XCTAssertTrue(store.activeTabs[0].sessionIds.contains(s2.id))
    }

    // MARK: - Execute: mergeTab

    func test_execute_mergeTab_combinesTabs() {
        // Arrange
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(.mergeTab(
            sourceTabId: tab2.id,
            targetTabId: tab1.id,
            targetPaneId: s1.id,
            direction: .right
        ))

        // Assert
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertTrue(store.activeTabs[0].isSplit)
    }

    // MARK: - OpenTerminal

    func test_openTerminal_createsSessionAndTab() {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()
        store.addRepo(at: repo.repoPath)

        // Act
        let session = executor.openTerminal(for: worktree, in: repo)

        // Assert
        XCTAssertNotNil(session)
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func test_openTerminal_existingSession_selectsTab() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        let worktree = makeWorktree(id: worktreeId)
        let repo = makeRepo(id: repoId)

        // Create first session manually
        let existingSession = store.createSession(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Existing"
        )
        let tab = Tab(sessionId: existingSession.id)
        store.appendTab(tab)

        // Act — try to open same worktree
        let result = executor.openTerminal(for: worktree, in: repo)

        // Assert — returns nil (already exists), tab selected
        XCTAssertNil(result)
        XCTAssertEqual(store.activeTabs.count, 1)
        XCTAssertEqual(store.activeTabId, tab.id)
    }
}
