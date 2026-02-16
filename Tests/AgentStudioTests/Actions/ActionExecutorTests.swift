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
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
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
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        XCTAssertEqual(store.tabs.count, 1)

        // Act
        executor.execute(.closeTab(tabId: tab.id))

        // Assert
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func test_execute_closeTab_pushesToUndoStack() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act
        executor.execute(.closeTab(tabId: tab.id))

        // Assert
        XCTAssertEqual(executor.undoStack.count, 1)
        XCTAssertEqual(executor.undoStack[0].tab.id, tab.id)
    }

    func test_execute_closeTab_multipleCloses_stacksUndo() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
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
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Undoable")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        executor.execute(.closeTab(tabId: tab.id))
        XCTAssertTrue(store.tabs.isEmpty)

        // Act
        executor.undoCloseTab()

        // Assert
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs[0].id, tab.id)
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
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: Set(layout.paneIds)
        )
        let tab = Tab(
            panes: layout.paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: p1.id
        )
        store.appendTab(tab)

        // Act
        executor.execute(.breakUpTab(tabId: tab.id))

        // Assert
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs[0].paneIds, [p1.id])
        XCTAssertEqual(store.tabs[1].paneIds, [p2.id])
    }

    // MARK: - Execute: extractPaneToTab

    func test_execute_extractPaneToTab_createsNewTab() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: Set(layout.paneIds)
        )
        let tab = Tab(
            panes: layout.paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: p1.id
        )
        store.appendTab(tab)

        // Act
        executor.execute(.extractPaneToTab(tabId: tab.id, paneId: p2.id))

        // Assert
        XCTAssertEqual(store.tabs.count, 2)
    }

    // MARK: - Execute: focusPane

    func test_execute_focusPane_setsActivePane() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: Set(layout.paneIds)
        )
        let tab = Tab(
            panes: layout.paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: p1.id
        )
        store.appendTab(tab)

        // Act
        executor.execute(.focusPane(tabId: tab.id, paneId: p2.id))

        // Assert
        XCTAssertEqual(store.tabs[0].activePaneId, p2.id)
    }

    // MARK: - Execute: resizePane

    func test_execute_resizePane_updatesRatio() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.insertPane(
            p2.id, inTab: tab.id, at: p1.id,
            direction: .horizontal, position: .after
        )

        // Get split ID
        guard case .split(let split) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }

        // Act
        executor.execute(.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3))

        // Assert
        guard case .split(let updatedSplit) = store.tabs[0].layout.root else {
            XCTFail("Expected split layout")
            return
        }
        XCTAssertEqual(updatedSplit.ratio, 0.3, accuracy: 0.001)
    }

    // MARK: - Execute: equalizePanes

    func test_execute_equalizePanes_resetsRatios() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.insertPane(
            p2.id, inTab: tab.id, at: p1.id,
            direction: .horizontal, position: .after
        )

        // Resize first
        guard case .split(let split) = store.tabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        store.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3)

        // Act
        executor.execute(.equalizePanes(tabId: tab.id))

        // Assert
        guard case .split(let eqSplit) = store.tabs[0].layout.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(eqSplit.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Execute: closePane

    func test_execute_closePane_removesFromLayout() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: Set(layout.paneIds)
        )
        let tab = Tab(
            panes: layout.paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: p1.id
        )
        store.appendTab(tab)

        // Act
        executor.execute(.closePane(tabId: tab.id, paneId: p1.id))

        // Assert
        XCTAssertEqual(store.tabs[0].paneIds, [p2.id])
        XCTAssertFalse(store.tabs[0].isSplit)
    }

    // MARK: - Execute: insertPane (existingPane)

    func test_execute_insertPane_existingPane_movesPane() {
        // Arrange — p2 in tab2, move to tab1 next to p1
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(.insertPane(
            source: .existingPane(paneId: p2.id, sourceTabId: tab2.id),
            targetTabId: tab1.id,
            targetPaneId: p1.id,
            direction: .right
        ))

        // Assert — tab2 was removed (last pane extracted), tab1 now has split
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertTrue(store.tabs[0].isSplit)
        XCTAssertTrue(store.tabs[0].paneIds.contains(p1.id))
        XCTAssertTrue(store.tabs[0].paneIds.contains(p2.id))
    }

    // MARK: - Execute: mergeTab

    func test_execute_mergeTab_combinesTabs() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(.mergeTab(
            sourceTabId: tab2.id,
            targetTabId: tab1.id,
            targetPaneId: p1.id,
            direction: .right
        ))

        // Assert
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertTrue(store.tabs[0].isSplit)
    }

    // MARK: - OpenTerminal

    func test_openTerminal_surfaceFails_rollsBackPane() {
        // Arrange — coordinator.createView() returns nil in tests (no Ghostty runtime)
        let worktree = makeWorktree()
        let repo = makeRepo()
        store.addRepo(at: repo.repoPath)

        // Act
        let pane = executor.openTerminal(for: worktree, in: repo)

        // Assert — surface creation failed, pane rolled back, no tab created
        XCTAssertNil(pane)
        XCTAssertTrue(store.tabs.isEmpty)
        XCTAssertEqual(store.panes.count, 0)
    }

    func test_openTerminal_existingPane_selectsTab() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        let worktree = makeWorktree(id: worktreeId)
        let repo = makeRepo(id: repoId)

        // Create first pane manually
        let existingPane = store.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Existing"
        )
        let tab = Tab(paneId: existingPane.id)
        store.appendTab(tab)

        // Act — try to open same worktree
        let result = executor.openTerminal(for: worktree, in: repo)

        // Assert — returns nil (already exists), tab selected
        XCTAssertNil(result)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabId, tab.id)
    }

    // MARK: - Undo GC

    func test_undoStack_expiresOldEntries() {
        // Arrange — close 12 tabs (exceeds maxUndoStackSize of 10)
        var closedPaneIds: [UUID] = []
        for i in 0..<12 {
            let pane = store.createPane(
                source: .floating(workingDirectory: nil, title: "Tab \(i)")
            )
            closedPaneIds.append(pane.id)
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            executor.execute(.closeTab(tabId: tab.id))
        }

        // Assert — undo stack is capped at 10
        XCTAssertEqual(executor.undoStack.count, 10)

        // The 2 oldest panes should be GC'd from the store
        // (they were in the expired undo entries and not in any layout)
        XCTAssertNil(store.pane(closedPaneIds[0]))
        XCTAssertNil(store.pane(closedPaneIds[1]))

        // The 10 newest should still be in the store (in the undo stack)
        XCTAssertNotNil(store.pane(closedPaneIds[2]))
        XCTAssertNotNil(store.pane(closedPaneIds[11]))
    }

    // MARK: - Execute: switchArrangement

    func test_execute_switchArrangement_updatesStoreState() {
        // Arrange: tab with panes A, B, C. Default arrangement has all 3.
        let pA = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pB = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pC = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        let tab = Tab(paneId: pA.id)
        store.appendTab(tab)
        store.insertPane(pB.id, inTab: tab.id, at: pA.id, direction: .horizontal, position: .after)
        store.insertPane(pC.id, inTab: tab.id, at: pB.id, direction: .horizontal, position: .after)

        // Create custom arrangement with only panes A and B
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([pA.id, pB.id]),
            inTab: tab.id
        )!

        // Act: switch to custom arrangement via executor
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: arrId))

        // Assert: tab.paneIds returns only A and B (from active arrangement)
        let updatedTab = store.tab(tab.id)!
        XCTAssertEqual(updatedTab.activeArrangementId, arrId)
        XCTAssertEqual(Set(updatedTab.paneIds), Set([pA.id, pB.id]))
        // Pane C is still owned by the tab but not visible in active arrangement
        XCTAssertTrue(updatedTab.panes.contains(pC.id))
        XCTAssertFalse(updatedTab.paneIds.contains(pC.id))
    }

    func test_execute_switchArrangement_backToDefault_restoresAllPanes() {
        // Arrange: tab with panes A, B, C
        let pA = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pB = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pC = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        let tab = Tab(paneId: pA.id)
        store.appendTab(tab)
        store.insertPane(pB.id, inTab: tab.id, at: pA.id, direction: .horizontal, position: .after)
        store.insertPane(pC.id, inTab: tab.id, at: pB.id, direction: .horizontal, position: .after)

        let customArrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([pA.id]),
            inTab: tab.id
        )!

        // Switch to custom (only A)
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: customArrId))
        XCTAssertEqual(store.tab(tab.id)!.paneIds, [pA.id])

        // Act: switch back to default
        let defaultArrId = store.tab(tab.id)!.defaultArrangement.id
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: defaultArrId))

        // Assert: all three panes visible again
        let updatedTab = store.tab(tab.id)!
        XCTAssertEqual(updatedTab.activeArrangementId, defaultArrId)
        XCTAssertEqual(Set(updatedTab.paneIds), Set([pA.id, pB.id, pC.id]))
    }

    func test_execute_switchArrangement_sameArrangement_noOp() {
        // Arrange
        let pA = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pA.id)
        store.appendTab(tab)

        let defaultArrId = store.tab(tab.id)!.activeArrangementId

        // Act: switch to same arrangement (should be no-op)
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: defaultArrId))

        // Assert: unchanged
        XCTAssertEqual(store.tab(tab.id)!.activeArrangementId, defaultArrId)
        XCTAssertEqual(store.tab(tab.id)!.paneIds, [pA.id])
    }

    func test_execute_switchArrangement_invalidTabId_noOp() {
        // Act: should not crash
        executor.execute(.switchArrangement(tabId: UUID(), arrangementId: UUID()))

        // Assert: no tabs affected
        XCTAssertTrue(store.tabs.isEmpty)
    }

    // MARK: - Execute: addDrawerPane

    func test_execute_addDrawerPane_createsDrawerOnActivePane() {
        // Arrange
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)

        let content = PaneContent.terminal(TerminalState(provider: .ghostty, lifetime: .temporary))
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer")

        // Act
        executor.execute(.addDrawerPane(parentPaneId: parentPane.id, content: content, metadata: metadata))

        // Assert
        let updated = store.pane(parentPane.id)
        XCTAssertNotNil(updated?.drawer)
        XCTAssertEqual(updated?.drawer?.panes.count, 1)
        XCTAssertTrue(updated?.drawer?.isExpanded ?? false)
    }

    // MARK: - Execute: removeDrawerPane

    func test_execute_removeDrawerPane_removesFromStore() {
        // Arrange
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)

        let drawerPane = store.addDrawerPane(
            to: parentPane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer")
        )!
        XCTAssertNotNil(store.pane(parentPane.id)?.drawer)
        XCTAssertEqual(store.pane(parentPane.id)?.drawer?.panes.count, 1)

        // Act
        executor.execute(.removeDrawerPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))

        // Assert — last drawer pane removed, drawer itself should be nil
        XCTAssertNil(store.pane(parentPane.id)?.drawer)
    }

    // MARK: - Execute: toggleDrawer

    func test_execute_toggleDrawer_togglesExpandedState() {
        // Arrange
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)

        _ = store.addDrawerPane(
            to: parentPane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer")
        )
        XCTAssertTrue(store.pane(parentPane.id)!.drawer!.isExpanded, "Drawer should be expanded by default")

        // Act — collapse
        executor.execute(.toggleDrawer(paneId: parentPane.id))

        // Assert — collapsed
        XCTAssertFalse(store.pane(parentPane.id)!.drawer!.isExpanded)

        // Act — expand again
        executor.execute(.toggleDrawer(paneId: parentPane.id))

        // Assert — expanded
        XCTAssertTrue(store.pane(parentPane.id)!.drawer!.isExpanded)
    }

    // MARK: - Execute: setActiveDrawerPane

    func test_execute_setActiveDrawerPane_switchesActive() {
        // Arrange
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)

        let dp1 = store.addDrawerPane(
            to: parentPane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "First")
        )!
        let dp2 = store.addDrawerPane(
            to: parentPane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Second")
        )!
        XCTAssertEqual(store.pane(parentPane.id)!.drawer!.activeDrawerPaneId, dp2.id, "Last added should be active")

        // Act
        executor.execute(.setActiveDrawerPane(parentPaneId: parentPane.id, drawerPaneId: dp2.id))

        // Assert
        XCTAssertEqual(store.pane(parentPane.id)!.drawer!.activeDrawerPaneId, dp2.id)
    }

    // MARK: - Execute: switchArrangement (ViewRegistry integration)

    func test_execute_switchArrangement_viewRegistryRetainsAllViews() {
        // Arrange: tab with 3 panes, each registered in ViewRegistry
        let pA = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pB = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pC = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        let tab = Tab(paneId: pA.id)
        store.appendTab(tab)
        store.insertPane(pB.id, inTab: tab.id, at: pA.id, direction: .horizontal, position: .after)
        store.insertPane(pC.id, inTab: tab.id, at: pB.id, direction: .horizontal, position: .after)

        // Register stub PaneViews for all 3 panes
        let viewA = PaneView(paneId: pA.id)
        let viewB = PaneView(paneId: pB.id)
        let viewC = PaneView(paneId: pC.id)
        viewRegistry.register(viewA, for: pA.id)
        viewRegistry.register(viewB, for: pB.id)
        viewRegistry.register(viewC, for: pC.id)

        // Create custom arrangement with only panes A and B
        let customArrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([pA.id, pB.id]),
            inTab: tab.id
        )!

        // Act: switch to custom arrangement (hides pane C)
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: customArrId))

        // Assert: all 3 views are still in the ViewRegistry
        XCTAssertNotNil(viewRegistry.view(for: pA.id), "View A should still be registered after arrangement switch")
        XCTAssertNotNil(viewRegistry.view(for: pB.id), "View B should still be registered after arrangement switch")
        XCTAssertNotNil(viewRegistry.view(for: pC.id), "View C should still be registered even though hidden")
        XCTAssertEqual(viewRegistry.registeredPaneIds, Set([pA.id, pB.id, pC.id]))

        // Verify the store correctly reflects only A and B as visible
        let updatedTab = store.tab(tab.id)!
        XCTAssertEqual(Set(updatedTab.paneIds), Set([pA.id, pB.id]))
        // But pane C is still owned by the tab
        XCTAssertTrue(updatedTab.panes.contains(pC.id))
    }

    func test_execute_switchArrangement_backToDefault_viewsStillRegistered() {
        // Arrange: tab with 3 panes, each registered in ViewRegistry
        let pA = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pB = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pC = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        let tab = Tab(paneId: pA.id)
        store.appendTab(tab)
        store.insertPane(pB.id, inTab: tab.id, at: pA.id, direction: .horizontal, position: .after)
        store.insertPane(pC.id, inTab: tab.id, at: pB.id, direction: .horizontal, position: .after)

        // Register stub PaneViews for all 3 panes
        let viewA = PaneView(paneId: pA.id)
        let viewB = PaneView(paneId: pB.id)
        let viewC = PaneView(paneId: pC.id)
        viewRegistry.register(viewA, for: pA.id)
        viewRegistry.register(viewB, for: pB.id)
        viewRegistry.register(viewC, for: pC.id)

        let epochBeforeSwitch = viewRegistry.epoch

        // Create custom arrangement with only pane A
        let customArrId = store.createArrangement(
            name: "Solo",
            paneIds: Set([pA.id]),
            inTab: tab.id
        )!

        // Act: switch to custom, then back to default
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: customArrId))
        let defaultArrId = store.tab(tab.id)!.defaultArrangement.id
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: defaultArrId))

        // Assert: all 3 views are still registered after round-trip
        XCTAssertNotNil(viewRegistry.view(for: pA.id), "View A should survive round-trip arrangement switch")
        XCTAssertNotNil(viewRegistry.view(for: pB.id), "View B should survive round-trip arrangement switch")
        XCTAssertNotNil(viewRegistry.view(for: pC.id), "View C should survive round-trip arrangement switch")
        XCTAssertEqual(viewRegistry.registeredPaneIds, Set([pA.id, pB.id, pC.id]))

        // Verify all panes are visible again in the default arrangement
        let updatedTab = store.tab(tab.id)!
        XCTAssertEqual(Set(updatedTab.paneIds), Set([pA.id, pB.id, pC.id]))

        // Epoch should have stayed the same (no register/unregister calls)
        XCTAssertEqual(viewRegistry.epoch, epochBeforeSwitch, "Registry epoch should not change during arrangement switches")
    }
}
