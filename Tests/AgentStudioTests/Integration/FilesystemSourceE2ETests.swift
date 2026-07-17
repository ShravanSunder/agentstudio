import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

extension E2ESerializedTests {
    @MainActor
    @Suite(.serialized)
    struct FilesystemSourceE2ETests {
        @Test("filesystem actor events flow through coordinator into workspace stores")
        func filesystemEventsFlowThroughCoordinatorIntoStores() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "filesystem-e2e")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

            let workspaceDir = repoURL.deletingLastPathComponent().appending(path: "workspace-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: workspaceDir) }
            let store = WorkspaceStore()
            let repo = store.addRepo(at: repoURL)
            let worktree = Worktree(
                repoId: repo.id,
                name: "main",
                path: repoURL,
                isMainWorktree: true
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            let reconciledWorktree = try #require(store.repo(repo.id)?.worktrees.first)

            let pane = store.createPane(
                launchDirectory: reconciledWorktree.path,
                title: "Filesystem E2E Pane",
                facets: PaneContextFacets(
                    repoId: repo.id, worktreeId: reconciledWorktree.id, cwd: reconciledWorktree.path),
            )
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let paneEventBus = EventBus<RuntimeEnvelope>()
            let filesystemSource = FilesystemGitPipeline(
                bus: paneEventBus,
                gitWorkingTreeProvider: ShellGitWorkingTreeStatusProvider(
                    processExecutor: DefaultProcessExecutor(timeout: 5))
            )
            let paneProjectionStore = PaneFilesystemProjectionAtom()
            let repoCache = RepoCacheAtom()
            let cacheCoordinator = WorkspaceCacheCoordinator(
                bus: paneEventBus,
                workspaceStore: store,
                repoCache: repoCache,
                scopeSyncHandler: { _ in }
            )
            cacheCoordinator.startConsuming()
            await filesystemSource.start()

            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: FilesystemE2ESurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: paneEventBus,
                filesystemSource: filesystemSource,
                paneFilesystemProjectionStore: paneProjectionStore,
                windowLifecycleStore: WindowLifecycleAtom()
            )
            coordinator.syncFilesystemRootsAndActivity()

            await eventually("filesystem root should be registered for worktree") {
                coordinator.filesystemRegisteredContextsByWorktreeId[reconciledWorktree.id] != nil
            }

            await filesystemSource.enqueueRawPathsForTesting(
                worktreeId: reconciledWorktree.id,
                paths: ["tracked.txt", "untracked.txt"]
            )

            await eventually("workspace cache git snapshot should update") {
                guard let snapshot = repoCache.worktreeEnrichmentByWorktreeId[reconciledWorktree.id]?.snapshot else {
                    return false
                }
                return snapshot.summary.changed >= 1 && snapshot.summary.untracked >= 1
            }

            await eventually("pane projection snapshot should update") {
                guard let snapshot = paneProjectionStore.snapshotsByPaneId[pane.id] else { return false }
                return snapshot.changedPaths.contains("tracked.txt")
                    && snapshot.changedPaths.contains("untracked.txt")
            }

            await coordinator.shutdown()
            await cacheCoordinator.shutdown()

            await eventually("filesystem source E2E should leave no subscribers behind") {
                await paneEventBus.subscriberCount == 0
            }
        }

        private func eventually(
            _ description: String,
            // High yield budget by design: we want scheduler-tolerant async
            // convergence without using wall-clock sleeps in tests.
            maxYields: Int = 300_000,
            condition: @escaping @MainActor () async -> Bool
        ) async {
            for _ in 0..<maxYields {
                if await condition() {
                    return
                }
                await Task.yield()
            }
            #expect(await condition(), "\(description) timed out")
        }
    }
}

@MainActor
private final class FilesystemE2ESurfaceManager:
    WorkspaceSurfaceManaging
{
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> = AsyncStream { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? { nil }

    func detach(_: UUID, reason _: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_: UUID) {}

    func destroy(_: UUID) {}
}
