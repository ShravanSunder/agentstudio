import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerCommandTests {
    private struct Harness {
        let store: WorkspaceStore
        let coordinator: PaneCoordinator
        let controller: PaneTabViewController
        let viewRegistry: ViewRegistry
        let surfaceManager: MockPaneTabCommandSurfaceManager
        let windowLifecycleStore: WindowLifecycleStore
        let tempDir: URL
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
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
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
            repoCache: WorkspaceRepoCache(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: store, repoCache: WorkspaceRepoCache()),
            viewRegistry: viewRegistry
        )
        return Harness(
            store: store,
            coordinator: coordinator,
            controller: controller,
            viewRegistry: viewRegistry,
            surfaceManager: surfaceManager,
            windowLifecycleStore: windowLifecycleStore,
            tempDir: tempDir
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

    @Test("execute newTab resolves worktree context from floating pane cwd")
    func executeNewTab_resolvesWorktreeContextFromFloatingPaneCwd() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = harness.store.createPane(
            source: .floating(workingDirectory: worktree.path.appending(path: "nested"), title: "Pane A"),
            title: "Pane A",
            provider: .zmx,
            facets: PaneContextFacets(cwd: worktree.path.appending(path: "nested"))
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.controller.execute(.newTab)

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(
            harness.surfaceManager.lastCreatedSurfaceMetadata?.workingDirectory
                == worktree.path.appending(path: "nested"))
    }

    @Test("execute newTab falls back to floating terminal creation when no worktree matches cwd")
    func executeNewTab_fallsBackToFloatingCreation() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let unknownCwd = harness.tempDir.appending(path: "outside-known-repos")
        try? FileManager.default.createDirectory(at: unknownCwd, withIntermediateDirectories: true)
        let pane = harness.store.createPane(
            source: .floating(workingDirectory: unknownCwd, title: "Pane A"),
            title: "Pane A",
            provider: .zmx,
            facets: PaneContextFacets(cwd: unknownCwd)
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.controller.execute(.newTab)

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.workingDirectory == unknownCwd)
    }

    @Test("terminated pane closes only the matching split pane")
    func handleTerminalProcessTerminated_closesOnlyMatchingSplitPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let primaryPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Primary",
            provider: .zmx
        )
        let terminatingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
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
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Surviving",
            provider: .zmx
        )
        let terminatingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
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

    @Test("command harness shares window lifecycle store across monitor and coordinator")
    func makeHarness_sharesWindowLifecycleStoreAcrossLifecycleBoundaries() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        #expect(
            harness.coordinator.windowLifecycleStore === harness.windowLifecycleStore
        )
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
