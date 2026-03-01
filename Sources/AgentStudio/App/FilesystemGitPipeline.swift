import Foundation

/// Composition root for app-wide filesystem facts + derived local git facts.
///
/// `FilesystemActor` owns filesystem ingestion/routing and emits filesystem facts.
/// `GitWorkingDirectoryProjector` subscribes to those facts and emits git snapshot projections.
final class FilesystemGitPipeline: PaneCoordinatorFilesystemSourceManaging, Sendable {
    private let filesystemActor: FilesystemActor
    private let gitWorkingDirectoryProjector: GitWorkingDirectoryProjector

    init(
        bus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared,
        gitStatusProvider: any GitStatusProvider = ShellGitStatusProvider(),
        fseventStreamClient: any FSEventStreamClient = NoopFSEventStreamClient(),
        gitCoalescingWindow: Duration = .milliseconds(200)
    ) {
        self.filesystemActor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fseventStreamClient
        )
        self.gitWorkingDirectoryProjector = GitWorkingDirectoryProjector(
            bus: bus,
            gitStatusProvider: gitStatusProvider,
            coalescingWindow: gitCoalescingWindow
        )
    }

    func start() async {
        await gitWorkingDirectoryProjector.start()
    }

    func shutdown() async {
        await filesystemActor.shutdown()
        await gitWorkingDirectoryProjector.shutdown()
    }

    func register(worktreeId: UUID, rootPath: URL) async {
        // Ensure projector subscription is active before lifecycle facts are posted.
        await gitWorkingDirectoryProjector.start()
        await filesystemActor.register(worktreeId: worktreeId, rootPath: rootPath)
    }

    func unregister(worktreeId: UUID) async {
        await filesystemActor.unregister(worktreeId: worktreeId)
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        await filesystemActor.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp)
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        await filesystemActor.setActivePaneWorktree(worktreeId: worktreeId)
    }

    func enqueueRawPathsForTesting(worktreeId: UUID, paths: [String]) async {
        await filesystemActor.enqueueRawPaths(worktreeId: worktreeId, paths: paths)
    }
}
