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
            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: workspaceDir))
            store.restore()

            let repo = store.addRepo(at: repoURL)
            let worktree = Worktree(
                name: "main",
                path: repoURL,
                branch: "main",
                isMainWorktree: true
            )
            store.updateRepoWorktrees(repo.id, worktrees: [worktree])

            let pane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id),
                title: "Filesystem E2E Pane"
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
            let paneProjectionStore = PaneFilesystemProjectionStore()
            let workspaceGitWorkingTreeStore = WorkspaceGitWorkingTreeStore()

            let coordinator = PaneCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: MockPaneCoordinatorSurfaceManagerFilesystemE2E(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: paneEventBus,
                filesystemSource: filesystemSource,
                paneFilesystemProjectionStore: paneProjectionStore,
                workspaceGitWorkingTreeStore: workspaceGitWorkingTreeStore
            )

            await eventually("filesystem root should be registered for worktree") {
                coordinator.filesystemRegisteredContextsByWorktreeId[worktree.id] != nil
            }

            await filesystemSource.enqueueRawPathsForTesting(
                worktreeId: worktree.id,
                paths: ["tracked.txt", "untracked.txt"]
            )

            await eventually("workspace git status snapshot should update") {
                guard let snapshot = workspaceGitWorkingTreeStore.snapshotsByWorktreeId[worktree.id] else {
                    return false
                }
                return snapshot.summary.changed >= 1 && snapshot.summary.untracked >= 1
            }

            await eventually("pane projection snapshot should update") {
                guard let snapshot = paneProjectionStore.snapshotsByPaneId[pane.id] else { return false }
                return snapshot.changedPaths.contains("tracked.txt")
                    && snapshot.changedPaths.contains("untracked.txt")
            }

            await filesystemSource.shutdown()
        }

        private func eventually(
            _ description: String,
            maxAttempts: Int = 200,
            pollIntervalNanoseconds: UInt64 = 20_000_000,
            condition: @escaping @MainActor () -> Bool
        ) async {
            for _ in 0..<maxAttempts {
                if condition() {
                    return
                }
                await Task.yield()
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
            #expect(condition(), "\(description) timed out")
        }
    }
}

@MainActor
private final class MockPaneCoordinatorSurfaceManagerFilesystemE2E: PaneCoordinatorSurfaceManaging {
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
