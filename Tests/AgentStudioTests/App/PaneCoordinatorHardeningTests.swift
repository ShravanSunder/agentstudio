import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorHardeningTests {
    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let surfaceManager: MockPaneCoordinatorSurfaceManager
        let tempDir: URL
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized)
    ) -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-hardening-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockPaneCoordinatorSurfaceManager(createSurfaceResult: createSurfaceResult)
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            surfaceManager: surfaceManager,
            tempDir: tempDir
        )
    }

    private func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "wt-main")
        try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(name: "wt-main", path: worktreePath, branch: "main")
        store.updateRepoWorktrees(repo.id, worktrees: [worktree])
        return (repo, worktree)
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: title), title: title)
        )
    }

    @Test("openTerminal rolls back pane and tab state when surface creation fails")
    func openTerminal_rollsBackOnSurfaceCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        guard let persistedRepo = harness.store.repo(repo.id) else {
            Issue.record("Expected repo to be persisted in WorkspaceStore")
            return
        }

        let openedPane = harness.coordinator.openTerminal(for: worktree, in: persistedRepo)

        #expect(openedPane == nil)
        #expect(harness.store.tabs.isEmpty)
        #expect(harness.store.panes.isEmpty)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("closeTab tears down views for panes hidden by non-active arrangements")
    func closeTab_tearsDownAllOwnedPaneViews() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let paneA = makeWebviewPane(harness.store, title: "A")
        let paneB = makeWebviewPane(harness.store, title: "B")
        let paneC = makeWebviewPane(harness.store, title: "C")
        let tab = Tab(paneId: paneA.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after
        )
        harness.store.insertPane(
            paneC.id,
            inTab: tab.id,
            at: paneB.id,
            direction: .horizontal,
            position: .after
        )
        guard
            let focusArrangementId = harness.store.createArrangement(
                name: "Focus AB",
                paneIds: Set([paneA.id, paneB.id]),
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: focusArrangementId, inTab: tab.id)

        harness.viewRegistry.register(PaneView(paneId: paneA.id), for: paneA.id)
        harness.viewRegistry.register(PaneView(paneId: paneB.id), for: paneB.id)
        harness.viewRegistry.register(PaneView(paneId: paneC.id), for: paneC.id)

        harness.coordinator.execute(.closeTab(tabId: tab.id))

        #expect(harness.store.tab(tab.id) == nil)
        #expect(harness.viewRegistry.registeredPaneIds.isEmpty)
        guard case .tab(let snapshot)? = harness.coordinator.undoStack.last else {
            Issue.record("Expected tab snapshot in undo stack")
            return
        }
        #expect(Set(snapshot.panes.map(\.id)) == Set([paneA.id, paneB.id, paneC.id]))
    }

    @Test("purgeOrphanedPane only purges panes that are backgrounded")
    func purgeOrphanedPane_requiresBackgroundedResidency() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeWebviewPane(harness.store, title: "Transient")
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.viewRegistry.register(PaneView(paneId: pane.id), for: pane.id)

        harness.coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
        #expect(harness.store.pane(pane.id) != nil)
        #expect(harness.viewRegistry.view(for: pane.id) != nil)

        harness.coordinator.execute(.backgroundPane(paneId: pane.id))
        harness.coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
        #expect(harness.store.pane(pane.id) == nil)
        #expect(harness.viewRegistry.view(for: pane.id) == nil)
    }

    @Test("insertPane newTerminal rolls back transient pane when terminal view creation fails")
    func insertPaneNewTerminal_rollsBackOnSurfaceCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let targetPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Target",
            provider: .zmx
        )
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.coordinator.execute(
            .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right
            )
        )

        #expect(Set(harness.store.panes.keys) == initialPaneIds)
        #expect(harness.store.tab(tab.id)?.paneIds == [targetPane.id])
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }
}

@MainActor
private final class MockPaneCoordinatorSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    private(set) var createSurfaceCallCount = 0

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
        return createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func destroy(_ surfaceId: UUID) {}
}
