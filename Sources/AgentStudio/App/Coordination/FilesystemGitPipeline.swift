import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

protocol WatchedFolderCommandHandling: AnyObject, Sendable {
    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary
    func refreshRegisteredWorktreesAndWatchedFolders(
        _ watchedPaths: [WatchedPath]
    ) async -> WatchedFolderRefreshSummary
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
    private let registrationValidator: GitWorktreeRegistrationValidator

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
        self.registrationValidator = GitWorktreeRegistrationValidator(
            delay: .clock(gitSleepClock)
        )
        self.forgeActor = ForgeActor(
            bus: bus,
            statusProvider: forgeStatusProvider,
            providerName: "github",
            performanceTraceRecorder: performanceTraceRecorder
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
        await forgeActor.setDemand(worktreeIds: [])
        await filesystemActor.shutdown()
        await gitWorkingDirectoryProjector.shutdown()
        await forgeActor.shutdown()
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        // Ensure projector subscription is active before lifecycle facts are posted.
        await startGitProjector()
        await startForgeActor()
        let context = WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
        switch await registrationValidator.registrationDecision(worktreeId: worktreeId, context: context) {
        case .validated:
            break
        case .authoritativeNegative:
            await forgeActor.unregister(worktreeId: worktreeId)
            await filesystemActor.unregister(worktreeId: worktreeId)
            return
        case .uncertain:
            return
        }
        await forgeActor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await filesystemActor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
    }

    func unregister(worktreeId: UUID) async {
        await registrationValidator.removeAcceptedContext(worktreeId: worktreeId)
        await forgeActor.unregister(worktreeId: worktreeId)
        await filesystemActor.unregister(worktreeId: worktreeId)
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        await startGitProjector()
        await registrationValidator.retainAcceptedContexts(
            worktreeIds: Set(assertion.contextsByWorktreeId.keys)
        )
        var validatedContextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:]
        for (worktreeId, context) in assertion.contextsByWorktreeId {
            switch await registrationValidator.registrationDecision(worktreeId: worktreeId, context: context) {
            case .validated:
                validatedContextsByWorktreeId[worktreeId] = context
            case .authoritativeNegative:
                continue
            case .uncertain(let previouslyAcceptedContext):
                if let previouslyAcceptedContext {
                    validatedContextsByWorktreeId[worktreeId] = previouslyAcceptedContext
                }
            }
        }
        let validatedAssertion = FilesystemTopologyAssertion(
            generation: assertion.generation,
            contextsByWorktreeId: validatedContextsByWorktreeId
        )
        await filesystemActor.assertTopology(validatedAssertion)
        await gitWorkingDirectoryProjector.assertTopology(validatedAssertion)
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

    func setPullRequestDemandWorktrees(_ worktreeIds: Set<UUID>) async {
        await forgeActor.setDemand(worktreeIds: worktreeIds)
    }

    func enqueueRawPathsForTesting(worktreeId: UUID, paths: [String]) async {
        await filesystemActor.enqueueRawPaths(worktreeId: worktreeId, paths: paths)
    }

    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary {
        let summary = await filesystemActor.refreshWatchedFolders(watchedPaths)
        if watchedPaths.isEmpty {
            await gitWorkingDirectoryProjector.refreshRegisteredWorktreesImmediately()
        } else {
            await gitWorkingDirectoryProjector.refreshRegisteredWorktreesIntersecting(watchedPaths.map(\.path))
        }
        return summary
    }

    func refreshRegisteredWorktreesAndWatchedFolders(
        _ watchedPaths: [WatchedPath]
    ) async -> WatchedFolderRefreshSummary {
        let summary = await filesystemActor.refreshWatchedFolders(watchedPaths)
        await gitWorkingDirectoryProjector.refreshRegisteredWorktreesImmediately()
        return summary
    }

    func applyScopeChange(_ change: ScopeChange) async {
        switch change {
        case .registerForgeRepo(let repoId, let remote):
            await forgeActor.setOrigin(repo: repoId, remote: remote)
        case .unregisterForgeRepo(let repoId):
            await forgeActor.removeRepository(repo: repoId)
        case .refreshForgeRepo(let repoId, let correlationId):
            await forgeActor.refresh(repo: repoId, correlationId: correlationId)
        case .updateWatchedFolders(let watchedPaths):
            _ = await filesystemActor.refreshWatchedFolders(watchedPaths)
        }
    }
}

private enum GitWorktreeRegistrationDecision: Sendable, Equatable {
    case validated
    case authoritativeNegative
    case uncertain(previouslyAcceptedContext: WorktreeFilesystemContext?)
}

private actor GitWorktreeRegistrationValidator {
    private let discoveryProvider: RepoScannerGitDiscoveryClient
    private let delay: AsyncDelay
    private var acceptedContextByWorktreeId: [UUID: WorktreeFilesystemContext] = [:]

    init(
        discoveryProvider: RepoScannerGitDiscoveryClient = RepoScannerGitDiscoveryClient(),
        delay: AsyncDelay = .taskSleep
    ) {
        self.discoveryProvider = discoveryProvider
        self.delay = delay
    }

    func registrationDecision(
        worktreeId: UUID,
        context: WorktreeFilesystemContext
    ) async -> GitWorktreeRegistrationDecision {
        for attempt in 1...AppPolicies.GitRefresh.registrationValidationMaximumAttempts {
            switch await discoveryProvider.discoveryOutcome(for: context.rootPath) {
            case .validated:
                acceptedContextByWorktreeId[worktreeId] = context
                return .validated
            case .authoritativeNegative:
                acceptedContextByWorktreeId.removeValue(forKey: worktreeId)
                return .authoritativeNegative
            case .timeout, .cancelled, .failure:
                guard attempt < AppPolicies.GitRefresh.registrationValidationMaximumAttempts else {
                    return .uncertain(previouslyAcceptedContext: acceptedContextByWorktreeId[worktreeId])
                }
                do {
                    try await delay.wait(AppPolicies.GitRefresh.registrationValidationRetryDelay)
                } catch {
                    return .uncertain(previouslyAcceptedContext: acceptedContextByWorktreeId[worktreeId])
                }
            }
        }
        return .uncertain(previouslyAcceptedContext: acceptedContextByWorktreeId[worktreeId])
    }

    func removeAcceptedContext(worktreeId: UUID) {
        acceptedContextByWorktreeId.removeValue(forKey: worktreeId)
    }

    func retainAcceptedContexts(worktreeIds: Set<UUID>) {
        acceptedContextByWorktreeId = acceptedContextByWorktreeId.filter { worktreeIds.contains($0.key) }
    }
}
