import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct WorkspaceSurfaceCoordinatorHarness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let tempDir: URL
    }

    private func makeHarnessCoordinator() -> WorkspaceSurfaceCoordinatorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: viewRegistry, runtime: runtime,
            windowLifecycleStore: WindowLifecycleAtom()
        )
        return WorkspaceSurfaceCoordinatorHarness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            tempDir: tempDir
        )
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(title: title)
        )
    }

    private func makeFilesystemSyncCoordinator(
        store: WorkspaceStore,
        filesystemSource: some WorkspaceFilesystemSourceManaging,
        paneEventBus: EventBus<RuntimeEnvelope>
    ) -> WorkspaceSurfaceCoordinator {
        WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockWorkspaceSurfaceCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: paneEventBus,
            filesystemSource: filesystemSource,
            windowLifecycleStore: WindowLifecycleAtom()
        )
    }

    private func reconciledWorktree(
        in store: WorkspaceStore,
        repoId: UUID,
        path: URL
    ) throws -> Worktree {
        try #require(store.repo(repoId)?.worktrees.first(where: { $0.path == path }))
    }

    private func appendAndActivateSingleTab(
        for paneId: UUID,
        in store: WorkspaceStore
    ) -> Tab {
        let tab = Tab(paneId: paneId)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        return tab
    }

    @Test
    func test_paneCoordinator_exposesExecuteAPI() async {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let action: WorkspaceActionCommand = .selectTab(tabId: UUID())
        harness.coordinator.execute(action)
    }

    @Test("undo close tab restores the tab and activates it")
    func undoCloseTab_restoresAndActivatesClosedTab() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tabA = Tab(paneId: paneA.id)
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabA)
        store.appendTab(tabB)
        store.setActiveTab(tabB.id)

        coordinator.execute(.closeTab(tabId: tabA.id))
        #expect(store.tab(tabA.id) == nil)
        #expect(store.activeTabId == tabB.id)
        #expect(coordinator.undoStack.count == 1)

        coordinator.undoCloseTab()

        #expect(store.tab(tabA.id) != nil)
        #expect(store.activeTabId == tabA.id)
        #expect(coordinator.undoStack.isEmpty)
    }

    @Test("close pane undo round-trips pane in layout")
    func closePane_undo_restoresPane() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        coordinator.execute(.closePane(tabId: tab.id, paneId: paneB.id))
        guard let afterClose = store.tab(tab.id) else {
            Issue.record("Expected tab to remain after closing one pane")
            return
        }
        #expect(afterClose.paneIds == [paneA.id])
        #expect(coordinator.undoStack.count == 1)

        coordinator.undoCloseTab()
        guard let afterUndo = store.tab(tab.id) else {
            Issue.record("Expected tab to exist after undo")
            return
        }
        #expect(afterUndo.paneIds.count == 2)
        #expect(Set(afterUndo.paneIds) == Set([paneA.id, paneB.id]))
    }

    @Test("closePane on the last pane in an active tab produces a TabCloseSnapshot")
    func closePane_lastPaneActive_producesTabSnapshot() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let pane = makeWebviewPane(store, title: "Solo")
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        coordinator.execute(.closePane(tabId: tab.id, paneId: pane.id))

        #expect(store.tab(tab.id) == nil)
        #expect(store.pane(pane.id) == nil)
        guard let entry = coordinator.undoStack.last else {
            Issue.record("Expected undo entry after last-pane close")
            return
        }
        switch entry {
        case .tab(let snapshot):
            #expect(snapshot.tab.id == tab.id)
        case .pane:
            Issue.record("Expected tab snapshot when closing the last pane")
        }
    }

    @Test("closePane on the last pane in a background tab still produces a TabCloseSnapshot")
    func closePane_lastPaneBackground_stillProducesTabSnapshot() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let activePane = makeWebviewPane(store, title: "Active")
        let activeTab = Tab(paneId: activePane.id)
        store.appendTab(activeTab)
        store.setActiveTab(activeTab.id)

        let backgroundPane = makeWebviewPane(store, title: "Background")
        let backgroundTab = Tab(paneId: backgroundPane.id)
        store.appendTab(backgroundTab)

        coordinator.execute(.closePane(tabId: backgroundTab.id, paneId: backgroundPane.id))

        #expect(store.tab(backgroundTab.id) == nil)
        guard case .tab(let snapshot)? = coordinator.undoStack.last else {
            Issue.record("Expected TabCloseSnapshot for background last-pane close")
            return
        }
        #expect(snapshot.tab.id == backgroundTab.id)
    }

    @Test("closePane on a non-last pane in an active tab produces a PaneCloseSnapshot")
    func closePane_nonLastPaneActive_producesPaneSnapshot() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )

        coordinator.execute(.closePane(tabId: tab.id, paneId: paneB.id))

        #expect(store.tab(tab.id) != nil)
        guard case .pane(let snapshot)? = coordinator.undoStack.last else {
            Issue.record("Expected PaneCloseSnapshot")
            return
        }
        #expect(snapshot.pane.id == paneB.id)
    }

    @Test("filesystem projection ignores non-projectable worktree events before deriving topology maps")
    func filesystemProjectionIgnoresNonProjectableWorktreeEvents() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-filesystem-ignore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore()
        let coordinator = makeFilesystemSyncCoordinator(
            store: store,
            filesystemSource: RecordingFilesystemSourceHarness(),
            paneEventBus: EventBus<RuntimeEnvelope>()
        )

        let envelope = RuntimeEnvelope.worktree(
            WorktreeEnvelope(
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                seq: 1,
                timestamp: ContinuousClock().now,
                repoId: UUID(),
                worktreeId: UUID(),
                event: .gitWorkingDirectory(.originChanged(repoId: UUID(), from: "", to: "origin"))
            )
        )

        #expect(await coordinator.handleFilesystemEnvelopeIfNeeded(envelope) == false)
    }

    @Test("closing tab with drawer children snapshots all panes for undo")
    func closeTab_withDrawerChildren_snapshotsUndo() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let parentPane = makeWebviewPane(store, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        guard let drawerPane = store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation to succeed")
            return
        }

        coordinator.execute(.closeTab(tabId: tab.id))

        #expect(store.tab(tab.id) == nil)
        #expect(store.tabs.allSatisfy { !$0.paneIds.contains(parentPane.id) })
        #expect(store.tabs.allSatisfy { !$0.paneIds.contains(drawerPane.id) })

        guard case .tab(let snapshot)? = coordinator.undoStack.last else {
            Issue.record("Expected tab close snapshot in undo stack")
            return
        }
        let snapshottedPaneIds = Set(snapshot.panes.map(\.id))
        #expect(snapshottedPaneIds.contains(parentPane.id))
        #expect(snapshottedPaneIds.contains(drawerPane.id))
    }

    @Test("openWebview creates and activates a new tab")
    func openWebview_createsAndActivatesTab() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator

        let opened = coordinator.openWebview(url: URL(string: "https://example.com/open-webview-test")!)
        guard let opened else {
            Issue.record("Expected webview pane to open")
            return
        }

        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs.first?.id)
        #expect(store.tab(store.tabs[0].id)?.paneIds == [opened.id])
        #expect(viewRegistry.view(for: opened.id) != nil)
    }

    @Test("teardownView unregisters runtime from RuntimeRegistry")
    func teardownViewUnregistersRuntime() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let runtimePaneId = PaneId.generateUUIDv7()
        let metadata = PaneMetadata(
            paneId: runtimePaneId,
            contentType: .browser,
            title: "Runtime Teardown"
        )
        let runtime = WebviewRuntime(
            paneId: runtimePaneId,
            metadata: metadata
        )
        runtime.transitionToReady()
        harness.coordinator.registerRuntime(runtime)

        #expect(harness.coordinator.runtimeForPane(runtimePaneId) != nil)
        harness.coordinator.teardownView(for: runtimePaneId.uuid)
        #expect(harness.coordinator.runtimeForPane(runtimePaneId) == nil)
    }

    @Test("focusPane auto-expands minimized pane")
    func focusPane_autoExpandsMinimizedPane() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        coordinator.execute(.minimizePane(tabId: tab.id, paneId: paneB.id))
        #expect(store.tab(tab.id)?.activeMinimizedPaneIds.contains(paneB.id) == true)

        coordinator.execute(.expandPane(tabId: tab.id, paneId: paneB.id))

        #expect(store.tab(tab.id)?.activeMinimizedPaneIds.contains(paneB.id) == false)
        #expect(store.tab(tab.id)?.activePaneId == paneB.id)
    }

    @Test("undo skips stale pane entries whose tab no longer exists")
    func undo_skipsStalePaneEntryWhenTabMissing() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        coordinator.execute(.closePane(tabId: tab.id, paneId: paneB.id))
        #expect(coordinator.undoStack.count == 1)

        store.removeTab(tab.id)
        coordinator.undoCloseTab()

        #expect(store.tab(tab.id) == nil)
        #expect(coordinator.undoStack.isEmpty)
    }

    @Test("undo stack keeps only max configured entries")
    func undoStack_capsAtMaxEntries() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        for index in 0..<12 {
            let pane = makeWebviewPane(store, title: "Pane-\(index)")
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            coordinator.execute(.closeTab(tabId: tab.id))
        }

        #expect(coordinator.undoStack.count == 10)
    }

    @Test("syncRootsAndActivity")
    func syncRootsAndActivity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-sync-roots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/repo-sync-roots-\(UUID().uuidString)"))
        guard let primaryWorktree = store.repo(repo.id)?.worktrees.first(where: \.isMainWorktree) else {
            Issue.record("Expected addRepo to create a main worktree")
            return
        }
        let secondaryWorktree = Worktree(
            repoId: repo.id,
            name: "feature-a",
            path: repo.repoPath.appending(path: "feature-a")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [primaryWorktree, secondaryWorktree])
        let reconciledSecondaryWorktree = try reconciledWorktree(
            in: store,
            repoId: repo.id,
            path: secondaryWorktree.path
        )

        let primaryPane = store.createPane(
            launchDirectory: primaryWorktree.path,
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: primaryWorktree.id,
                cwd: primaryWorktree.path
            )
        )
        _ = appendAndActivateSingleTab(for: primaryPane.id, in: store)

        let filesystemSource = RecordingFilesystemSource()
        let paneEventBus = EventBus<RuntimeEnvelope>()
        let coordinator = makeFilesystemSyncCoordinator(
            store: store,
            filesystemSource: filesystemSource,
            paneEventBus: paneEventBus
        )

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([primaryWorktree.id, reconciledSecondaryWorktree.id])
                && snapshot.activityByWorktreeId[primaryWorktree.id] == true
                && snapshot.activityByWorktreeId[reconciledSecondaryWorktree.id] == false
                && snapshot.activePaneWorktreeId == primaryWorktree.id
        }

        let tertiaryWorktree = Worktree(
            repoId: repo.id,
            name: "feature-b",
            path: repo.repoPath.appending(path: "feature-b")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [primaryWorktree, tertiaryWorktree])
        let reconciledTertiaryWorktree = try reconciledWorktree(
            in: store,
            repoId: repo.id,
            path: tertiaryWorktree.path
        )
        coordinator.topologyDidChange(
            WorktreeTopologyDelta(
                repoId: repo.id,
                addedWorktreeIds: [reconciledTertiaryWorktree.id],
                removedWorktrees: [
                    RemovedWorktreeEntry(id: reconciledSecondaryWorktree.id, path: reconciledSecondaryWorktree.path)
                ],
                preservedWorktreeIds: [primaryWorktree.id],
                didChange: true,
                traceId: nil
            )
        )

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([primaryWorktree.id, reconciledTertiaryWorktree.id])
                && snapshot.activityByWorktreeId[primaryWorktree.id] == true
                && snapshot.activityByWorktreeId[reconciledTertiaryWorktree.id] == false
                && snapshot.activePaneWorktreeId == primaryWorktree.id
        }

        let tertiaryPane = store.createPane(
            launchDirectory: reconciledTertiaryWorktree.path,
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: reconciledTertiaryWorktree.id,
                cwd: reconciledTertiaryWorktree.path
            )
        )
        let tertiaryTab = Tab(paneId: tertiaryPane.id)
        store.appendTab(tertiaryTab)
        coordinator.upsertPaneFilesystemProjectionContext(for: tertiaryPane)
        coordinator.execute(WorkspaceActionCommand.selectTab(tabId: tertiaryTab.id))

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            snapshot.activityByWorktreeId[reconciledTertiaryWorktree.id] == true
                && snapshot.activePaneWorktreeId == reconciledTertiaryWorktree.id
        }
    }

    @Test("syncRootsAndActivity excludes unavailable repos from filesystem registration")
    func syncRootsAndActivityExcludesUnavailableRepos() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-sync-unavailable-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/repo-sync-unavailable-\(UUID().uuidString)"))
        store.markRepoUnavailable(repo.id)

        let filesystemSource = RecordingFilesystemSource()
        let paneEventBus = EventBus<RuntimeEnvelope>()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockWorkspaceSurfaceCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: paneEventBus,
            filesystemSource: filesystemSource,
            windowLifecycleStore: WindowLifecycleAtom()
        )

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            snapshot.registeredRoots.isEmpty
                && snapshot.activityByWorktreeId.isEmpty
                && snapshot.activePaneWorktreeId == nil
        }

        _ = coordinator
    }

    @Test("filesystem sync converges to latest roots when updates arrive during an in-flight pass")
    func syncRootsAndActivityConvergesUnderInFlightUpdates() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-sync-converge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/repo-sync-converge-\(UUID().uuidString)"))
        guard let mainWorktree = store.repo(repo.id)?.worktrees.first(where: \.isMainWorktree) else {
            Issue.record("Expected addRepo to create a main worktree")
            return
        }
        let staleWorktree = Worktree(
            repoId: repo.id,
            name: "stale-branch",
            path: repo.repoPath.appending(path: "stale-branch")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, staleWorktree])
        let reconciledStaleWorktree = try #require(
            store.repo(repo.id)?.worktrees.first(where: { $0.path == staleWorktree.path })
        )

        let primaryPane = store.createPane(
            launchDirectory: mainWorktree.path,
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: mainWorktree.id,
                cwd: mainWorktree.path
            )
        )
        let primaryTab = Tab(paneId: primaryPane.id)
        store.appendTab(primaryTab)
        store.setActiveTab(primaryTab.id)

        let filesystemSource = DelayingRecordingFilesystemSource(operationDelayTurns: 32)
        let paneEventBus = EventBus<RuntimeEnvelope>()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockWorkspaceSurfaceCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: paneEventBus,
            filesystemSource: filesystemSource,
            windowLifecycleStore: WindowLifecycleAtom()
        )
        _ = coordinator

        // Trigger a second desired state while the initial sync pass is still executing.
        let latestWorktree = Worktree(
            repoId: repo.id,
            name: "latest-branch",
            path: repo.repoPath.appending(path: "latest-branch")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, latestWorktree])
        coordinator.topologyDidChange(
            WorktreeTopologyDelta(
                repoId: repo.id,
                addedWorktreeIds: [latestWorktree.id],
                removedWorktrees: [
                    RemovedWorktreeEntry(id: reconciledStaleWorktree.id, path: reconciledStaleWorktree.path)
                ],
                preservedWorktreeIds: [mainWorktree.id],
                didChange: true,
                traceId: nil
            )
        )

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .seconds(2)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([mainWorktree.id, latestWorktree.id])
                && snapshot.registeredRoots[reconciledStaleWorktree.id] == nil
                && snapshot.activityByWorktreeId[mainWorktree.id] == true
                && snapshot.activityByWorktreeId[latestWorktree.id] == false
                && snapshot.activePaneWorktreeId == mainWorktree.id
        }
    }

    @Test("topology effect handler with no removed worktrees still syncs roots and does not orphan panes")
    func topologyEffectHandlerWithoutRemovedWorktreesStillSyncsRoots() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-empty-delta-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/repo-empty-delta-\(UUID().uuidString)"))
        guard let mainWorktree = store.repo(repo.id)?.worktrees.first(where: \.isMainWorktree) else {
            Issue.record("Expected addRepo to create main worktree")
            return
        }

        let pane = store.createPane(
            launchDirectory: mainWorktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let filesystemSource = RecordingFilesystemSource()
        let coordinator = makeFilesystemSyncCoordinator(
            store: store,
            filesystemSource: filesystemSource,
            paneEventBus: EventBus<RuntimeEnvelope>()
        )
        _ = coordinator

        let newWorktree = Worktree(
            repoId: repo.id,
            name: "feature-added",
            path: repo.repoPath.appending(path: "feature-added")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, newWorktree])
        let reconciledNewWorktree = try reconciledWorktree(
            in: store,
            repoId: repo.id,
            path: newWorktree.path
        )

        coordinator.topologyDidChange(
            WorktreeTopologyDelta(
                repoId: repo.id,
                addedWorktreeIds: [reconciledNewWorktree.id],
                removedWorktrees: [],
                preservedWorktreeIds: [mainWorktree.id],
                didChange: true,
                traceId: nil
            )
        )

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([mainWorktree.id, reconciledNewWorktree.id])
        }

        let updatedPane = try #require(store.pane(pane.id))
        #expect(updatedPane.residency == .active)
    }

    private func waitUntilFilesystemState(
        source: RecordingFilesystemSource,
        timeout _: Duration,
        condition: @escaping @Sendable (FilesystemSourceSnapshot) -> Bool
    ) async {
        for _ in 0..<200 {
            let snapshot = await source.snapshot()
            if condition(snapshot) {
                return
            }
            await Task.yield()
        }

        let finalSnapshot = await source.snapshot()
        Issue.record("Timed out waiting for filesystem sync state. Snapshot: \(String(describing: finalSnapshot))")
    }

    private func waitUntilFilesystemState(
        source: DelayingRecordingFilesystemSource,
        timeout _: Duration,
        condition: @escaping @Sendable (FilesystemSourceSnapshot) -> Bool
    ) async {
        for _ in 0..<200 {
            let snapshot = await source.snapshot()
            if condition(snapshot) {
                return
            }
            await Task.yield()
        }

        let finalSnapshot = await source.snapshot()
        Issue.record(
            "Timed out waiting for delayed filesystem sync state. Snapshot: \(String(describing: finalSnapshot))")
    }
}

private struct FilesystemSourceSnapshot: Sendable, CustomStringConvertible {
    let registeredRoots: [UUID: URL]
    let activityByWorktreeId: [UUID: Bool]
    let activePaneWorktreeId: UUID?

    var description: String {
        "registered=\(registeredRoots.keys.map(\.uuidString).sorted()) "
            + "activity=\(activityByWorktreeId.mapValues { $0 ? "active" : "idle" }) "
            + "activePaneWorktree=\(activePaneWorktreeId?.uuidString ?? "nil")"
    }
}

private actor RecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private(set) var registeredRoots: [UUID: URL] = [:]
    private(set) var activityByWorktreeId: [UUID: Bool] = [:]
    private(set) var activePaneWorktreeId: UUID?
    private(set) var topologyAssertionGeneration: UInt64?

    func start() async {}

    func shutdown() async {}

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) {
        registeredRoots[worktreeId] = rootPath
    }

    func unregister(worktreeId: UUID) {
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        guard topologyAssertionGeneration.map({ assertion.generation >= $0 }) ?? true else { return }
        topologyAssertionGeneration = assertion.generation
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        registeredRoots = assertion.contextsByWorktreeId.mapValues(\.rootPath)
        activityByWorktreeId = activityByWorktreeId.filter { desiredWorktreeIds.contains($0.key) }
        if let activePaneWorktreeId, !desiredWorktreeIds.contains(activePaneWorktreeId) {
            self.activePaneWorktreeId = nil
        }
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        activityByWorktreeId[worktreeId] = isActiveInApp
    }

    func setActivePaneWorktree(worktreeId: UUID?) {
        activePaneWorktreeId = worktreeId
    }

    func snapshot() -> FilesystemSourceSnapshot {
        FilesystemSourceSnapshot(
            registeredRoots: registeredRoots,
            activityByWorktreeId: activityByWorktreeId,
            activePaneWorktreeId: activePaneWorktreeId
        )
    }
}

private actor DelayingRecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private let operationDelayTurns: Int
    private(set) var registeredRoots: [UUID: URL] = [:]
    private(set) var activityByWorktreeId: [UUID: Bool] = [:]
    private(set) var activePaneWorktreeId: UUID?
    private(set) var topologyAssertionGeneration: UInt64?

    init(operationDelayTurns: Int) {
        self.operationDelayTurns = operationDelayTurns
    }

    func start() async {}

    func shutdown() async {}

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        await settleDelay()
        registeredRoots[worktreeId] = rootPath
    }

    func unregister(worktreeId: UUID) async {
        await settleDelay()
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        await settleDelay()
        guard topologyAssertionGeneration.map({ assertion.generation >= $0 }) ?? true else { return }
        topologyAssertionGeneration = assertion.generation
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        registeredRoots = assertion.contextsByWorktreeId.mapValues(\.rootPath)
        activityByWorktreeId = activityByWorktreeId.filter { desiredWorktreeIds.contains($0.key) }
        if let activePaneWorktreeId, !desiredWorktreeIds.contains(activePaneWorktreeId) {
            self.activePaneWorktreeId = nil
        }
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        await settleDelay()
        activityByWorktreeId[worktreeId] = isActiveInApp
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        await settleDelay()
        activePaneWorktreeId = worktreeId
    }

    func snapshot() -> FilesystemSourceSnapshot {
        FilesystemSourceSnapshot(
            registeredRoots: registeredRoots,
            activityByWorktreeId: activityByWorktreeId,
            activePaneWorktreeId: activePaneWorktreeId
        )
    }

    private func settleDelay() async {
        for _ in 0..<operationDelayTurns {
            await Task.yield()
        }
    }
}

private final class MockWorkspaceSurfaceCoordinatorSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> {
        cwdStream
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.operationFailed("mock"))
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
