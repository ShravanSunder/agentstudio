import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class ActionExecutorTests {

    private var store: WorkspaceStore!
    private var viewRegistry: ViewRegistry!
    private var coordinator: TerminalViewCoordinator!
    private var runtime: SessionRuntime!
    private var executor: ActionExecutor!
    private var tempDir: URL!

    init() {
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

    deinit {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        executor = nil
        coordinator = nil
        runtime = nil
        viewRegistry = nil
        store = nil
    }

    // MARK: - Execute: selectTab

    
    @Test
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
        #expect(store.activeTabId == tab2.id)
    }

    // MARK: - Execute: closeTab

    
    @Test
    func test_execute_closeTab_removesTab() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        #expect(store.tabs.count == 1)

        // Act
        executor.execute(.closeTab(tabId: tab.id))

        // Assert
        #expect(store.tabs.isEmpty)
    }

    
    @Test
    func test_execute_closeTab_pushesToUndoStack() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act
        executor.execute(.closeTab(tabId: tab.id))

        // Assert
        #expect(executor.undoStack.count == 1)
        if case .tab(let snapshot) = executor.undoStack[0] {
            #expect(snapshot.tab.id == tab.id)
        } else {
            Issue.record("Expected .tab entry")
        }
    }

    
    @Test
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
        #expect(executor.undoStack.count == 2)
        if case .tab(let s1) = executor.undoStack[0] {
            #expect(s1.tab.id == tab1.id)
        } else {
            Issue.record("Expected .tab entry at index 0")
        }
        if case .tab(let s2) = executor.undoStack[1] {
            #expect(s2.tab.id == tab2.id)
        } else {
            Issue.record("Expected .tab entry at index 1")
        }
    }

    // MARK: - Undo Close Tab

    
    @Test
    func test_undoCloseTab_restoresTab() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Undoable")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        executor.execute(.closeTab(tabId: tab.id))
        #expect(store.tabs.isEmpty)

        // Act
        executor.undoCloseTab()

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].id == tab.id)
        #expect(executor.undoStack.isEmpty)
    }

    
    @Test
    func test_undoCloseTab_emptyStack_noOp() {
        // Act — should not crash
        executor.undoCloseTab()

        // Assert
        #expect(executor.undoStack.isEmpty)
    }

    // MARK: - Execute: breakUpTab

    
    @Test
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
        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].paneIds == [p1.id])
        #expect(store.tabs[1].paneIds == [p2.id])
    }

    // MARK: - Execute: extractPaneToTab

    
    @Test
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
        #expect(store.tabs.count == 2)
    }

    // MARK: - Execute: focusPane

    
    @Test
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
        #expect(store.tabs[0].activePaneId == p2.id)
    }

    // MARK: - Execute: resizePane

    
    @Test
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
            Issue.record("Expected split layout")
            return
        }

        // Act
        executor.execute(.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3))

        // Assert
        guard case .split(let updatedSplit) = store.tabs[0].layout.root else {
            Issue.record("Expected split layout")
            return
        }
        #expect(abs(updatedSplit.ratio - 0.3) < 0.001)
    }

    // MARK: - Execute: equalizePanes

    
    @Test
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
            Issue.record("Expected split")
            return
        }
        store.resizePane(tabId: tab.id, splitId: split.id, ratio: 0.3)

        // Act
        executor.execute(.equalizePanes(tabId: tab.id))

        // Assert
        guard case .split(let eqSplit) = store.tabs[0].layout.root else {
            Issue.record("Expected split")
            return
        }
        #expect(abs(eqSplit.ratio - 0.5) < 0.001)
    }

    // MARK: - Execute: closePane

    
    @Test
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
        #expect(store.tabs[0].paneIds == [p2.id])
        #expect(!(store.tabs[0].isSplit))
    }

    // MARK: - Execute: insertPane (existingPane)

    
    @Test
    func test_execute_insertPane_existingPane_movesPane() {
        // Arrange — p2 in tab2, move to tab1 next to p1
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(
            .insertPane(
                source: .existingPane(paneId: p2.id, sourceTabId: tab2.id),
                targetTabId: tab1.id,
                targetPaneId: p1.id,
                direction: .right
            ))

        // Assert — tab2 was removed (last pane extracted), tab1 now has split
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].isSplit)
        #expect(store.tabs[0].paneIds.contains(p1.id))
        #expect(store.tabs[0].paneIds.contains(p2.id))
    }

    // MARK: - Execute: mergeTab

    
    @Test
    func test_execute_mergeTab_combinesTabs() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        executor.execute(
            .mergeTab(
                sourceTabId: tab2.id,
                targetTabId: tab1.id,
                targetPaneId: p1.id,
                direction: .right
            ))

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].isSplit)
    }

    // MARK: - OpenTerminal

    
    @Test
    func test_openTerminal_surfaceFails_rollsBackPane() {
        // Arrange — coordinator.createView() returns nil in tests (no Ghostty runtime)
        let worktree = makeWorktree()
        let repo = makeRepo()
        store.addRepo(at: repo.repoPath)

        // Act
        let pane = executor.openTerminal(for: worktree, in: repo)

        // Assert — surface creation failed, pane rolled back, no tab created
        #expect(pane == nil)
        #expect(store.tabs.isEmpty)
        #expect(store.panes.count == 0)
    }

    
    @Test
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
        #expect(result == nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == tab.id)
    }

    // MARK: - Undo GC

    
    @Test
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
        #expect(executor.undoStack.count == 10)

        // The 2 oldest panes should be GC'd from the store
        // (they were in the expired undo entries and not in any layout)
        #expect(store.pane(closedPaneIds[0]) == nil)
        #expect(store.pane(closedPaneIds[1]) == nil)

        // The 10 newest should still be in the store (in the undo stack)
        #expect(store.pane(closedPaneIds[2]) != nil)
        #expect(store.pane(closedPaneIds[11]) != nil)
    }

    // MARK: - Execute: switchArrangement

    
    @Test
    func test_computeSwitchArrangementTransitions_includesPreviouslyMinimizedVisiblePaneInReattachSet() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let previousVisiblePaneIds: Set<UUID> = [paneA, paneB]
        let previouslyMinimizedPaneIds: Set<UUID> = [paneB]
        let newVisiblePaneIds: Set<UUID> = [paneB, paneC]

        // Act
        let transitions = ActionExecutor.computeSwitchArrangementTransitions(
            previousVisiblePaneIds: previousVisiblePaneIds,
            previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
            newVisiblePaneIds: newVisiblePaneIds
        )

        // Assert
        #expect(transitions.hiddenPaneIds == Set([paneA]))
        #expect(transitions.paneIdsToReattach == Set([paneB, paneC]))
    }

    
    @Test
    func test_computeSwitchArrangementTransitions_whenNoMinimizedPanes_reattachesOnlyRevealedPanes() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let previousVisiblePaneIds: Set<UUID> = [paneA, paneB]
        let previouslyMinimizedPaneIds: Set<UUID> = []
        let newVisiblePaneIds: Set<UUID> = [paneB, paneC]

        // Act
        let transitions = ActionExecutor.computeSwitchArrangementTransitions(
            previousVisiblePaneIds: previousVisiblePaneIds,
            previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
            newVisiblePaneIds: newVisiblePaneIds
        )

        // Assert
        #expect(transitions.hiddenPaneIds == Set([paneA]))
        #expect(transitions.paneIdsToReattach == Set([paneC]))
    }

    
    @Test
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
        #expect(updatedTab.activeArrangementId == arrId)
        #expect(Set(updatedTab.paneIds) == Set([pA.id, pB.id]))
        // Pane C is still owned by the tab but not visible in active arrangement
        #expect(updatedTab.panes.contains(pC.id))
        #expect(!(updatedTab.paneIds.contains(pC.id)))
    }

    
    @Test
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
        #expect(store.tab(tab.id)!.paneIds == [pA.id])

        // Act: switch back to default
        let defaultArrId = store.tab(tab.id)!.defaultArrangement.id
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: defaultArrId))

        // Assert: all three panes visible again
        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.activeArrangementId == defaultArrId)
        #expect(Set(updatedTab.paneIds) == Set([pA.id, pB.id, pC.id]))
    }

    
    @Test
    func test_execute_switchArrangement_sameArrangement_noOp() {
        // Arrange
        let pA = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pA.id)
        store.appendTab(tab)

        let defaultArrId = store.tab(tab.id)!.activeArrangementId

        // Act: switch to same arrangement (should be no-op)
        executor.execute(.switchArrangement(tabId: tab.id, arrangementId: defaultArrId))

        // Assert: unchanged
        #expect(store.tab(tab.id)!.activeArrangementId == defaultArrId)
        #expect(store.tab(tab.id)!.paneIds == [pA.id])
    }

    
    @Test
    func test_execute_switchArrangement_invalidTabId_noOp() {
        // Act: should not crash
        executor.execute(.switchArrangement(tabId: UUID(), arrangementId: UUID()))

        // Assert: no tabs affected
        #expect(store.tabs.isEmpty)
    }

    // MARK: - Execute: switchArrangement (ViewRegistry integration)

    
    @Test
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
        #expect(viewRegistry.view(for: pA.id) != nil) // View A should still be registered after arrangement switch
        #expect(viewRegistry.view(for: pB.id) != nil) // View B should still be registered after arrangement switch
        #expect(viewRegistry.view(for: pC.id) != nil) // View C should still be registered even though hidden
        #expect(viewRegistry.registeredPaneIds == Set([pA.id, pB.id, pC.id]))

        // Verify the store correctly reflects only A and B as visible
        let updatedTab = store.tab(tab.id)!
        #expect(Set(updatedTab.paneIds) == Set([pA.id, pB.id]))
        // But pane C is still owned by the tab
        #expect(updatedTab.panes.contains(pC.id))
    }

    
    @Test
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
        #expect(viewRegistry.view(for: pA.id) != nil) // View A should survive round-trip arrangement switch
        #expect(viewRegistry.view(for: pB.id) != nil) // View B should survive round-trip arrangement switch
        #expect(viewRegistry.view(for: pC.id) != nil) // View C should survive round-trip arrangement switch
        #expect(viewRegistry.registeredPaneIds == Set([pA.id, pB.id, pC.id]))

        // Verify all panes are visible again in the default arrangement
        let updatedTab = store.tab(tab.id)!
        #expect(Set(updatedTab.paneIds) == Set([pA.id, pB.id, pC.id]))
    }

    // MARK: - Execute: repair (viewRevision)

    
    @Test
    func test_viewRevision_defaultsToZero() {
        // Assert
        #expect(store.viewRevision == 0)
    }

    
    @Test
    func test_executeRepair_recreateSurface_bumpsViewRevision() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        let stubView = PaneView(paneId: pane.id)
        viewRegistry.register(stubView, for: pane.id)
        #expect(store.viewRevision == 0)

        // Act
        executor.execute(.repair(.recreateSurface(paneId: pane.id)))

        // Assert
        #expect(store.viewRevision == 1)
    }

    
    @Test
    func test_executeRepair_createMissingView_bumpsViewRevision() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        #expect(store.viewRevision == 0)

        // Act
        executor.execute(.repair(.createMissingView(paneId: pane.id)))

        // Assert
        #expect(store.viewRevision == 1)
    }

    
    @Test
    func test_executeRepair_unknownPane_doesNotBumpViewRevision() {
        // Arrange
        let unknownId = UUID()
        #expect(store.viewRevision == 0)

        // Act
        executor.execute(.repair(.recreateSurface(paneId: unknownId)))

        // Assert — guard early-returns, no bump
        #expect(store.viewRevision == 0)
    }
}
