import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorCWDIdentityTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("surface cwd changed updates pane worktree identity")
    func surfaceCwdChangedUpdatesPaneWorktreeIdentity() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-surface-cwd-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = CWDIdentitySurfaceManager()
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/surface-cwd-identity-repo"))
        let mainWorktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: repo.repoPath,
            isMainWorktree: true
        )
        let featureWorktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: repo.repoPath.appending(path: "../surface-cwd-identity-repo-feature"),
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, featureWorktree])
        let pane = store.createPane(
            launchDirectory: mainWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let newCwd = featureWorktree.path.appending(path: "Sources")
        surfaceManager.sendCWDChange(surfaceId: UUID(), paneId: pane.id, cwd: newCwd)

        await eventually("surface cwd should refresh pane identity") {
            store.pane(pane.id)?.worktreeId == featureWorktree.id
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.cwd == newCwd)
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == featureWorktree.id)
        #expect(updated?.metadata.worktreeName == "feature")
        #expect(updated?.metadata.launchDirectory == pane.metadata.launchDirectory)

        await coordinator.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("surface cwd changed clears stale worktree identity when cwd leaves known worktrees")
    func surfaceCwdChangedClearsStaleWorktreeIdentityWhenCwdLeavesKnownWorktrees() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-surface-cwd-clears-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let surfaceManager = CWDIdentitySurfaceManager()
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/cwd-clear-repo"))
        let mainWorktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: repo.repoPath,
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree])
        let pane = store.createPane(
            launchDirectory: mainWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        store.appendTab(Tab(paneId: pane.id))

        let outsideKnownWorktrees = URL(filePath: "/tmp/project-dev")
        surfaceManager.sendCWDChange(surfaceId: UUID(), paneId: pane.id, cwd: outsideKnownWorktrees)

        await eventually("surface cwd outside topology should clear pane worktree identity") {
            store.pane(pane.id)?.metadata.cwd == outsideKnownWorktrees
                && store.pane(pane.id)?.repoId == nil
                && store.pane(pane.id)?.worktreeId == nil
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.launchDirectory == pane.metadata.launchDirectory)
        #expect(updated?.metadata.cwd == outsideKnownWorktrees)
        #expect(updated?.repoId == nil)
        #expect(updated?.worktreeId == nil)
        #expect(PaneDisplayDerived().displayParts(for: updated!).primaryLabel == "project-dev")

        await coordinator.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime cwd event preserves normalized full cwd and refreshes live identity")
    func runtimeCwdEventPreservesNormalizedFullCwdAndRefreshesLiveIdentity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-cwd-\(UUID().uuidString)")
        let bus = makeTestPaneRuntimeEventBus()
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: CWDIdentitySurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/runtime-cwd-repo"))
        let mainWorktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: repo.repoPath,
            isMainWorktree: true
        )
        let featureWorktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/runtime-cwd-repo-feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, featureWorktree])
        let pane = store.createPane(
            launchDirectory: mainWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        store.appendTab(Tab(paneId: pane.id))

        let rawCwdPath = "/tmp/runtime-cwd-repo-feature/../runtime-cwd-repo-feature/Sources"
        let expectedCwd = try #require(CWDNormalizer.normalize(rawCwdPath))
        _ = await bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .terminal(.cwdChanged(rawCwdPath)),
                paneId: PaneId(uuid: pane.id)
            )
        )

        await eventually("runtime cwd event should refresh pane live identity") {
            store.pane(pane.id)?.metadata.cwd == expectedCwd
                && store.pane(pane.id)?.worktreeId == featureWorktree.id
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.launchDirectory == pane.metadata.launchDirectory)
        #expect(updated?.metadata.cwd == expectedCwd)
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == featureWorktree.id)
        #expect(updated?.metadata.worktreeName == "feature")
        #expect(PaneDisplayDerived().displayParts(for: updated!).worktreeFolderName == "feature")

        await coordinator.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("surface cwd changed enriches live facets while preserving launch directory")
    func surfaceCwdChangedEnrichesLiveFacetsWhilePreservingLaunchDirectory() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-floating-cwd-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let surfaceManager = CWDIdentitySurfaceManager()
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/floating-cwd-repo"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "floating-target",
            path: URL(filePath: "/tmp/floating-cwd-repo/floating-target")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let pane = store.createPane(
            launchDirectory: URL(filePath: "/tmp/scratch"),
            title: "Scratch Terminal"
        )
        store.appendTab(Tab(paneId: pane.id))

        surfaceManager.sendCWDChange(surfaceId: UUID(), paneId: pane.id, cwd: worktree.path.appending(path: "Sources"))

        await eventually("floating cwd should refresh pane live identity") {
            store.pane(pane.id)?.repoId == repo.id
                && store.pane(pane.id)?.worktreeId == worktree.id
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.launchDirectory == pane.metadata.launchDirectory)
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == worktree.id)
        #expect(updated?.metadata.worktreeName == "floating-target")

        await coordinator.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }
}

@MainActor
private final class CWDIdentitySurfaceManager: PaneCoordinatorSurfaceManaging {
    private let continuation: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>.Continuation
    let surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        let stream = AsyncStream.makeStream(of: SurfaceManager.SurfaceCWDChangeEvent.self)
        self.surfaceCWDChanges = stream.stream
        self.continuation = stream.continuation
    }

    func sendCWDChange(surfaceId: UUID, paneId: UUID?, cwd: URL?) {
        continuation.yield(
            SurfaceManager.SurfaceCWDChangeEvent(surfaceId: surfaceId, paneId: paneId, cwd: cwd)
        )
    }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
