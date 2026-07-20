import Foundation

struct WatchedFolderRefreshSummary: Sendable, Equatable {
    let repoPathsByWatchedFolder: [URL: [URL]]

    func repoPaths(in watchedFolder: URL) -> [URL] {
        repoPathsByWatchedFolder[watchedFolder.standardizedFileURL, default: []]
    }
}

protocol WatchedFolderCommandHandling: AnyObject, Sendable {
    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary
}

/// Composition root for app-wide filesystem facts + derived local git facts.
///
/// `FilesystemActor` owns filesystem ingestion/routing and emits filesystem facts.
/// `GitWorkingDirectoryProjector` subscribes to those facts and emits git snapshot projections.
final class FilesystemGitPipeline: WorkspaceFilesystemSourceManaging, WatchedFolderCommandHandling,
    Sendable
{
    private let filesystemActor: FilesystemActor
    private let gitWorkingDirectoryProjector: GitWorkingDirectoryProjector
    private let forgeActor: ForgeActor

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        gitWorkingTreeProvider: any GitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(),
        forgeStatusProvider: any ForgeStatusProvider = GitHubCLIForgeStatusProvider(),
        fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient(),
        filesystemDebounceWindow: Duration = AppPolicies.GitRefresh.filesystemDebounceWindow,
        filesystemMaxFlushLatency: Duration = AppPolicies.GitRefresh.filesystemMaxFlushLatency,
        gitCoalescingWindow: Duration = AppPolicies.GitRefresh.filesystemDerivedCoalescingWindow,
        gitPeriodicRefreshInterval: Duration? = nil,
        gitRefreshPolicy: AppPolicies.GitRefresh.Policy = AppPolicies.GitRefresh.defaultPolicy,
        gitSleepClock: any Clock<Duration> & Sendable = ContinuousClock(),
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.filesystemActor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fseventStreamClient,
            debounceWindow: filesystemDebounceWindow,
            maxFlushLatency: filesystemMaxFlushLatency,
            performanceTraceRecorder: performanceTraceRecorder
        )
        self.gitWorkingDirectoryProjector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: gitWorkingTreeProvider,
            coalescingWindow: gitCoalescingWindow,
            periodicRefreshInterval: gitPeriodicRefreshInterval ?? gitRefreshPolicy.activeCadence,
            sleepClock: gitSleepClock,
            refreshPolicy: gitRefreshPolicy,
            performanceTraceRecorder: performanceTraceRecorder,
            pathExistenceProbe: GitWorkingDirectoryProjector.liveRootPathProbe
        )
        self.forgeActor = ForgeActor(
            bus: bus,
            statusProvider: forgeStatusProvider,
            providerName: "github"
        )
    }

    func start() async {
        await startFilesystemActor()
        await startGitProjector()
        await startForgeActor()
    }

    func startFilesystemActor() async {
        await filesystemActor.start()
    }

    func startGitProjector() async {
        await gitWorkingDirectoryProjector.start()
    }

    func startForgeActor() async {
        await forgeActor.start()
    }

    func shutdown() async {
        await filesystemActor.shutdown()
        await gitWorkingDirectoryProjector.shutdown()
        await forgeActor.shutdown()
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        // Ensure projector subscription is active before lifecycle facts are posted.
        await startGitProjector()
        await startForgeActor()
        await filesystemActor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
    }

    func unregister(worktreeId: UUID) async {
        await filesystemActor.unregister(worktreeId: worktreeId)
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        await startGitProjector()
        await filesystemActor.assertTopology(assertion)
        await gitWorkingDirectoryProjector.assertTopology(assertion)
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        await filesystemActor.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp)
        await gitWorkingDirectoryProjector.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp)
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        await filesystemActor.setActivePaneWorktree(worktreeId: worktreeId)
        await gitWorkingDirectoryProjector.setActivePaneWorktree(worktreeId: worktreeId)
    }

    func setSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) async {
        await gitWorkingDirectoryProjector.setSidebarVisibleWorktrees(worktreeIds)
    }

    func enqueueRawPathsForTesting(worktreeId: UUID, paths: [String]) async {
        await filesystemActor.enqueueRawPaths(worktreeId: worktreeId, paths: paths)
    }

    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary {
        await filesystemActor.refreshWatchedFolders(watchedPaths)
    }

    func applyScopeChange(_ change: ScopeChange) async {
        switch change {
        case .registerForgeRepo(let repoId, let remote):
            await forgeActor.register(repo: repoId, remote: remote)
        case .unregisterForgeRepo(let repoId):
            await forgeActor.unregister(repo: repoId)
        case .refreshForgeRepo(let repoId, let correlationId):
            await forgeActor.refresh(repo: repoId, correlationId: correlationId)
        case .updateWatchedFolders(let watchedPaths):
            _ = await filesystemActor.refreshWatchedFolders(watchedPaths)
        }
    }
}
