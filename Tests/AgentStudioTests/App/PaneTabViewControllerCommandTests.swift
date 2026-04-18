import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct Harness {
        let store: WorkspaceStore
        let coordinator: PaneCoordinator
        let executor: ActionExecutor
        let controller: PaneTabViewController
        let viewRegistry: ViewRegistry
        let surfaceManager: MockPaneTabCommandSurfaceManager
        let windowLifecycleStore: WindowLifecycleAtom
        let tempDir: URL
        let tabRenamePopoverState: TabRenamePopoverState
        let arrangementInlineRenameState: ArrangementInlineRenameState
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized)
    ) -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-tab-command-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockPaneTabCommandSurfaceManager(createSurfaceResult: createSurfaceResult)
        let runtimeRegistry = RuntimeRegistry()
        let appLifecycleStore = AppLifecycleAtom()
        let windowLifecycleStore = WindowLifecycleAtom()
        let tabRenamePopoverState = TabRenamePopoverState()
        let arrangementInlineRenameState = ArrangementInlineRenameState()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: runtimeRegistry,
            windowLifecycleStore: windowLifecycleStore
        )
        let executor = ActionExecutor(coordinator: coordinator, store: store)
        let controller = PaneTabViewController(
            store: store,
            repoCache: RepoCacheAtom(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: store, repoCache: RepoCacheAtom()),
            viewRegistry: viewRegistry,
            tabRenamePopoverState: tabRenamePopoverState,
            arrangementInlineRenameState: arrangementInlineRenameState
        )
        return Harness(
            store: store,
            coordinator: coordinator,
            executor: executor,
            controller: controller,
            viewRegistry: viewRegistry,
            surfaceManager: surfaceManager,
            windowLifecycleStore: windowLifecycleStore,
            tempDir: tempDir,
            tabRenamePopoverState: tabRenamePopoverState,
            arrangementInlineRenameState: arrangementInlineRenameState
        )
    }

    private func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "wt-main")
        try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "wt-main", path: worktreePath)
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        return (repo, worktree)
    }

    private func expectWebviewContent(_ pane: Pane, issuePrefix: String) {
        if case .webview = pane.content {
        } else {
            Issue.record("\(issuePrefix): expected created pane to be a webview")
        }
    }

    @Test("execute newTab uses first watched folder as cwd fallback")
    func executeNewTab_usesFirstWatchedFolderAsFallback() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let watchedFolder = harness.tempDir.appending(path: "watched-root")
        try? FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        _ = harness.store.repositoryTopologyAtom.addWatchedPath(watchedFolder)
        harness.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.controller.execute(.newTab)

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(
            harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd?.standardizedFileURL
                == watchedFolder.standardizedFileURL
        )
    }

    @Test("execute newTab falls back to user home when no watched folder exists")
    func executeNewTab_fallsBackToUserHome() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.controller.execute(.newTab)

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(
            harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd
                == FileManager.default.homeDirectoryForCurrentUser
        )
    }

    @Test("targeted renameTab presents the anchored popover for the selected tab")
    func executeRenameTab_targetedTab_presentsRenamePopoverForSelectedTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
        let firstTab = Tab(paneId: firstPane.id, name: "First Tab")
        let secondTab = Tab(paneId: secondPane.id, name: "Second Tab")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)

        harness.controller.execute(.renameTab, target: secondTab.id, targetType: .tab)

        #expect(harness.tabRenamePopoverState.presentedTabId == secondTab.id)
        #expect(harness.store.activeTabId == secondTab.id)
        #expect(harness.store.tab(secondTab.id)?.name == "Second Tab")
    }

    @Test("targeted renameTab ignores stale tab targets")
    func executeRenameTab_missingTarget_doesNotPresentRenamePopover() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id, name: "Only Tab")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let missingTabId = UUID()

        harness.controller.execute(.renameTab, target: missingTabId, targetType: .tab)

        #expect(harness.tabRenamePopoverState.presentedTabId == nil)
        #expect(harness.store.activeTabId == tab.id)
    }

    @Test("targeted renameArrangement begins inline edit on arrangement in the active tab")
    func executeRenameArrangement_activeTabArrangement_beginsInlineEdit() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after
        )
        harness.store.setActiveTab(tab.id)
        guard
            let customArrangementId = harness.store.createArrangement(
                name: "Layout 1",
                paneIds: [firstPane.id],
                inTab: tab.id
            )
        else {
            Issue.record("expected arrangement to be created")
            return
        }

        harness.controller.execute(.renameArrangement, target: customArrangementId, targetType: .tab)

        #expect(harness.arrangementInlineRenameState.editingArrangementId == customArrangementId)
        #expect(harness.arrangementInlineRenameState.draftName == "Layout 1")
        #expect(harness.store.activeTabId == tab.id)
    }

    @Test("targeted renameArrangement switches to the owning tab before beginning inline edit")
    func executeRenameArrangement_crossTabArrangement_switchesTabFirst() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstTabPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondTabPaneA = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second A"))
        let secondTabPaneB = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second B"))
        let firstTab = Tab(paneId: firstTabPane.id, name: "First")
        let secondTab = Tab(paneId: secondTabPaneA.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.insertPane(
            secondTabPaneB.id,
            inTab: secondTab.id,
            at: secondTabPaneA.id,
            direction: .horizontal,
            position: .after
        )
        harness.store.setActiveTab(firstTab.id)
        guard
            let customArrangementId = harness.store.createArrangement(
                name: "Layout 1",
                paneIds: [secondTabPaneA.id],
                inTab: secondTab.id
            )
        else {
            Issue.record("expected arrangement to be created")
            return
        }

        harness.controller.execute(.renameArrangement, target: customArrangementId, targetType: .tab)

        #expect(harness.store.activeTabId == secondTab.id)
        #expect(harness.arrangementInlineRenameState.editingArrangementId == customArrangementId)
        #expect(harness.arrangementInlineRenameState.draftName == "Layout 1")
    }

    @Test("targeted renameArrangement ignores the default arrangement")
    func executeRenameArrangement_defaultArrangement_isIgnored() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let defaultArrangementId = harness.store.tab(tab.id)?.defaultArrangement.id ?? UUID()

        harness.controller.execute(.renameArrangement, target: defaultArrangementId, targetType: .tab)

        #expect(harness.arrangementInlineRenameState.editingArrangementId == nil)
        #expect(harness.arrangementInlineRenameState.draftName.isEmpty)
    }

    @Test("targeted renameArrangement ignores a stale arrangement id")
    func executeRenameArrangement_unknownArrangement_isIgnored() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.renameArrangement, target: UUID(), targetType: .tab)

        #expect(harness.arrangementInlineRenameState.editingArrangementId == nil)
        #expect(harness.store.activeTabId == tab.id)
    }

    @Test("terminated pane closes only the matching split pane")
    func handleTerminalProcessTerminated_closesOnlyMatchingSplitPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let primaryPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Primary",
            provider: .zmx
        )
        let terminatingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminating",
            provider: .zmx
        )
        let tab = Tab(paneId: primaryPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            terminatingPane.id,
            inTab: tab.id,
            at: primaryPane.id,
            direction: .horizontal,
            position: .after
        )

        harness.controller.handleTerminalProcessTerminated(paneId: terminatingPane.id)

        #expect(harness.store.tab(tab.id)?.paneIds == [primaryPane.id])
        #expect(harness.store.pane(primaryPane.id) != nil)
        #expect(harness.store.pane(terminatingPane.id) == nil)
        #expect(harness.viewRegistry.terminalStatusPlaceholderView(for: terminatingPane.id) == nil)
    }

    @Test("terminated pane closes only the matching tab when multiple tabs share a worktree")
    func handleTerminalProcessTerminated_closesOnlyMatchingTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let survivingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Surviving",
            provider: .zmx
        )
        let terminatingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminating",
            provider: .zmx
        )
        let survivingTab = Tab(paneId: survivingPane.id, name: "Surviving")
        let terminatingTab = Tab(paneId: terminatingPane.id, name: "Terminating")
        harness.store.appendTab(survivingTab)
        harness.store.appendTab(terminatingTab)
        harness.store.setActiveTab(terminatingTab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: terminatingPane.id)

        #expect(harness.store.tab(survivingTab.id) != nil)
        #expect(harness.store.tab(terminatingTab.id) == nil)
        #expect(harness.store.pane(survivingPane.id) != nil)
    }

    @Test("terminated hidden pane closes without removing visible sibling or creating undo")
    func handleTerminalProcessTerminated_hiddenPaneClosesWithoutUndoEntry() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Visible",
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Hidden",
            provider: .zmx
        )
        let tab = Tab(paneId: visiblePane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            hiddenPane.id,
            inTab: tab.id,
            at: visiblePane.id,
            direction: .horizontal,
            position: .after
        )
        let focusArrangementId = harness.store.createArrangement(
            name: "Focus Visible",
            paneIds: [visiblePane.id],
            inTab: tab.id
        )!
        harness.store.switchArrangement(to: focusArrangementId, inTab: tab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: hiddenPane.id)

        #expect(harness.store.pane(visiblePane.id) != nil)
        #expect(harness.store.pane(hiddenPane.id) == nil)
        #expect(harness.store.tab(tab.id)?.visiblePaneIds == [visiblePane.id])
        #expect(harness.executor.undoStack.isEmpty)
    }

    @Test("terminated pane in a background tab does not create undo")
    func handleTerminalProcessTerminated_backgroundTabPaneClosesWithoutUndoEntry() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "First"),
            title: "First",
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Second"),
            title: "Second",
            provider: .zmx
        )
        let foregroundPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Foreground"),
            title: "Foreground",
            provider: .zmx
        )
        let backgroundTab = Tab(paneId: firstPane.id, name: "Background")
        let foregroundTab = Tab(paneId: foregroundPane.id, name: "Foreground")
        harness.store.appendTab(backgroundTab)
        harness.store.insertPane(
            secondPane.id,
            inTab: backgroundTab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after
        )
        harness.store.appendTab(foregroundTab)
        harness.store.setActiveTab(foregroundTab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: firstPane.id)

        #expect(harness.store.pane(firstPane.id) == nil)
        #expect(harness.store.tab(backgroundTab.id) != nil)
        #expect(harness.executor.undoStack.isEmpty)
    }

    @Test("terminated drawer child under a hidden parent does not create undo")
    func handleTerminalProcessTerminated_hiddenDrawerChildClosesWithoutUndoEntry() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let visiblePane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Visible"),
            title: "Visible",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            visiblePane.id,
            inTab: tab.id,
            at: parentPane.id,
            direction: .horizontal,
            position: .after
        )
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }
        let focusedVisibleArrangementId = harness.store.createArrangement(
            name: "Visible only",
            paneIds: Set([visiblePane.id]),
            inTab: tab.id
        )!
        harness.store.switchArrangement(to: focusedVisibleArrangementId, inTab: tab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: drawerPane.id)

        #expect(harness.store.pane(drawerPane.id) == nil)
        #expect(harness.store.pane(parentPane.id) != nil)
        #expect(harness.executor.undoStack.isEmpty)
    }

    @Test("command harness shares window lifecycle store across monitor and coordinator")
    func makeHarness_sharesWindowLifecycleStoreAcrossLifecycleBoundaries() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        #expect(
            harness.coordinator.windowLifecycleStore === harness.windowLifecycleStore
        )
    }

    @Test("toggleManagementLayer preserves drawer scope while exiting management layer")
    func executeToggleManagementLayer_preservesDrawerScopeOnExit() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        // Intentional: this covers the path where drawer pane selection
        // establishes the management navigation scope after mode is already active.
        atom(\.managementLayer).activate()
        harness.controller.setManagementNavigationScopeToDrawerForTesting(parentPaneId: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)

        #expect(!atom(\.managementLayer).isActive)
        #expect(
            harness.controller.managementLayerNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("managementLayerCreateTerminal targets drawer after drawer pane selection")
    func executeManagementCreateTerminal_selectedDrawerTargetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        atom(\.managementLayer).activate()

        harness.controller.handlePaneFocusTrigger(
            .drawer(.selectPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))
        )

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        #expect(
            harness.controller.managementLayerNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("managementLayerCreateTerminal in main row adds a split pane to the active tab")
    func executeManagementCreateTerminal_mainRowTargetsActiveTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty ?? true)
        #expect(harness.controller.managementLayerNavigationScopeDescriptionForTesting == "mainRow")
    }

    @Test("management layer entry adopts expanded drawer scope for create terminal")
    func executeManagementCreateTerminal_afterEnteringManagementLayerWithExpandedDrawer_targetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let existingDrawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        #expect(
            harness.controller.managementLayerNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
        #expect(harness.store.pane(existingDrawerPane.id) != nil)
    }

    @Test("managementLayerCreateBrowser targets drawer after drawer pane selection")
    func executeManagementCreateBrowser_selectedDrawerTargetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        atom(\.managementLayer).activate()

        harness.controller.handlePaneFocusTrigger(
            .drawer(.selectPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))
        )

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        expectWebviewContent(createdPane, issuePrefix: "drawer selection browser creation")
        #expect(
            harness.controller.managementLayerNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("managementLayerCreateBrowser in main row adds a split webview pane to the active tab")
    func executeManagementCreateBrowser_mainRowTargetsActiveTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))
        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty ?? true)
        expectWebviewContent(createdPane, issuePrefix: "main-row browser creation")
        #expect(harness.controller.managementLayerNavigationScopeDescriptionForTesting == "mainRow")
    }

    @Test("management layer entry adopts expanded drawer scope for create browser")
    func executeManagementCreateBrowser_afterEnteringManagementLayerWithExpandedDrawer_targetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        expectWebviewContent(createdPane, issuePrefix: "entry drawer browser creation")
        #expect(
            harness.controller.managementLayerNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("collapsed drawer falls back to main row for management terminal creation")
    func executeManagementCreateTerminal_afterDrawerDismiss_targetsMainRow() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)
        harness.controller.execute(.toggleDrawer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore)
        #expect(harness.controller.managementLayerNavigationScopeDescriptionForTesting == "mainRow")
    }

    @Test("collapsed drawer falls back to main row for management browser creation")
    func executeManagementCreateBrowser_afterDrawerDismiss_targetsMainRow() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)
        harness.controller.execute(.toggleDrawer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore)
        expectWebviewContent(createdPane, issuePrefix: "collapsed drawer browser creation")
        #expect(harness.controller.managementLayerNavigationScopeDescriptionForTesting == "mainRow")
    }

}

private final class MockPaneTabCommandSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    private(set) var createSurfaceCallCount = 0
    private(set) var lastCreatedSurfaceMetadata: SurfaceMetadata?

    init(createSurfaceResult: Result<ManagedSurface, SurfaceError>) {
        self.createSurfaceResult = createSurfaceResult
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceCallCount += 1
        lastCreatedSurfaceMetadata = metadata
        return createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
