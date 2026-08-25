import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

protocol WatchedFolderCommandHandling: AnyObject, Sendable {
    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary
    func filesystemLogicalDebtCount() async -> Int
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
    private let remoteReferenceRefreshActor: RemoteReferenceRefreshActor
    private let forgeActor: ForgeActor
    private let registrationValidator: GitWorktreeRegistrationValidator

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        registrationDiscoveryProvider: any RepoScanner.GitRepositoryDiscoveryProvider =
            RepoScannerGitDiscoveryClient(),
        gitWorkingTreeProvider: any GitWorkingTreeStatusProvider,
        remoteReferenceRefreshProvider: any RemoteReferenceRefreshProviding =
            AgentStudioGitRemoteReferenceRefreshProvider(),
        forgeStatusProvider: any ForgeStatusProvider = GitHubCLIForgeStatusProvider(),
        fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient(),
        filesystemDebounceWindow: Duration = AppPolicies.GitRefresh.filesystemDebounceWindow,
        filesystemMaxFlushLatency: Duration = AppPolicies.GitRefresh.filesystemMaxFlushLatency,
        gitCoalescingWindow: Duration = AppPolicies.GitRefresh.filesystemDerivedCoalescingWindow,
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
        let remoteReferenceAuthoritySink = RemoteReferenceAuthoritySink()
        let remoteReferenceRefreshActor = RemoteReferenceRefreshActor(
            provider: remoteReferenceRefreshProvider,
            performanceRecorder: performanceTraceRecorder,
            onAuthorityUpdate: { update in
                await remoteReferenceAuthoritySink.send(update)
            }
        )
        self.remoteReferenceRefreshActor = remoteReferenceRefreshActor
        let gitWorkingDirectoryProjector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: gitWorkingTreeProvider,
            coalescingWindow: gitCoalescingWindow,
            sleepClock: gitSleepClock,
            refreshPolicy: gitRefreshPolicy,
            performanceTraceRecorder: performanceTraceRecorder,
            remoteReferenceOriginHandler: { repoId, expectedOrigin in
                await remoteReferenceRefreshActor.setOrigin(repoId: repoId, expectedOrigin: expectedOrigin)
            },
            pathExistenceProbe: GitWorkingDirectoryProjector.liveRootPathProbe
        )
        self.gitWorkingDirectoryProjector = gitWorkingDirectoryProjector
        remoteReferenceAuthoritySink.install { update in
            await gitWorkingDirectoryProjector.applyRemoteReferenceAuthorityUpdate(update)
        }
        self.registrationValidator = GitWorktreeRegistrationValidator(
            discoveryProvider: registrationDiscoveryProvider
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
        await remoteReferenceRefreshActor.setDemand(repositoryIds: [])
        await filesystemActor.shutdown()
        await remoteReferenceRefreshActor.shutdown()
        await gitWorkingDirectoryProjector.shutdown()
        await forgeActor.shutdown()
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        // Ensure projector subscription is active before lifecycle facts are posted.
        await startGitProjector()
        await startForgeActor()
        let context = WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
        switch await registrationValidator.registrationDecision(context: context) {
        case .validated:
            break
        case .authoritativeNegative:
            await forgeActor.unregister(worktreeId: worktreeId)
            await remoteReferenceRefreshActor.unregister(worktreeId: worktreeId)
            await filesystemActor.unregister(worktreeId: worktreeId)
            return
        }
        await remoteReferenceRefreshActor.register(
            repoId: repoId,
            worktreeId: worktreeId,
            repositoryPath: rootPath,
            remoteName: "origin",
            expectedOrigin: nil
        )
        await forgeActor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await filesystemActor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
    }

    func unregister(worktreeId: UUID) async {
        await forgeActor.unregister(worktreeId: worktreeId)
        await remoteReferenceRefreshActor.unregister(worktreeId: worktreeId)
        await filesystemActor.unregister(worktreeId: worktreeId)
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        await startGitProjector()
        // Probes are independent libgit2 discovery reads; run them concurrently so one slow or
        // stalled worktree cannot serialize the whole fleet behind it.
        let validatedContextsByWorktreeId = await withTaskGroup(
            of: (UUID, WorktreeFilesystemContext?).self,
            returning: [UUID: WorktreeFilesystemContext].self
        ) { group in
            for (worktreeId, context) in assertion.contextsByWorktreeId {
                group.addTask { [registrationValidator] in
                    switch await registrationValidator.registrationDecision(context: context) {
                    case .validated:
                        return (worktreeId, context)
                    case .authoritativeNegative:
                        return (worktreeId, nil)
                    }
                }
            }
            var validatedContexts: [UUID: WorktreeFilesystemContext] = [:]
            for await (worktreeId, context) in group {
                if let context {
                    validatedContexts[worktreeId] = context
                }
            }
            return validatedContexts
        }
        let validatedAssertion = FilesystemTopologyAssertion(
            generation: assertion.generation,
            contextsByWorktreeId: validatedContextsByWorktreeId
        )
        await filesystemActor.assertTopology(validatedAssertion)
        await remoteReferenceRefreshActor.assertTopology(validatedContextsByWorktreeId)
        await gitWorkingDirectoryProjector.assertTopology(validatedAssertion)
    }

    func setRepositoryFactDemand(_ snapshot: RepositoryFactDemandSnapshot) async {
        await filesystemActor.setRepositoryFactAttention(
            activePaneWorktreeId: snapshot.activePaneWorktreeId,
            openWorktreeIds: snapshot.openWorktreeIds
        )
        await gitWorkingDirectoryProjector.setRepositoryFactAttention(
            activePaneWorktreeId: snapshot.activePaneWorktreeId,
            sidebarAttendedWorktreeIds: snapshot.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: snapshot.visibleActiveTabWorktreeIds,
            openWorktreeIds: snapshot.openWorktreeIds
        )
        await remoteReferenceRefreshActor.setDemand(repositoryIds: snapshot.demandedRepositoryIds)
        await forgeActor.setDemand(worktreeIds: snapshot.forgeDemandedWorktreeIds)
    }

    func waitForRepositoryFactDemandAdmission() async {
        await gitWorkingDirectoryProjector.waitForVisibilityAdmission()
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

    func filesystemLogicalDebtCount() async -> Int {
        await filesystemActor.logicalDebtCount()
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
            await remoteReferenceRefreshActor.setOrigin(repoId: repoId, expectedOrigin: remote)
            await forgeActor.setOrigin(repo: repoId, remote: remote)
        case .unregisterForgeRepo(let repoId):
            await remoteReferenceRefreshActor.setOrigin(repoId: repoId, expectedOrigin: nil)
            await forgeActor.removeRepository(repo: repoId)
        case .refreshForgeRepo(let repoId, let correlationId):
            await remoteReferenceRefreshActor.refresh(repoId: repoId)
            await forgeActor.refresh(repo: repoId, correlationId: correlationId)
        case .updateWatchedFolders(let watchedPaths):
            _ = await filesystemActor.refreshWatchedFolders(watchedPaths)
        }
    }
}

private final class RemoteReferenceAuthoritySink: @unchecked Sendable {
    typealias Handler = @Sendable (RemoteReferenceAuthorityUpdate) async -> Void

    private let lock = NSLock()
    private var handler: Handler?

    func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func send(_ update: RemoteReferenceAuthorityUpdate) async {
        let handler = lock.withLock { self.handler }
        await handler?(update)
    }
}

enum GitWorktreeRegistrationDecision: Sendable, Equatable {
    case validated
    case authoritativeNegative
}

actor GitWorktreeRegistrationValidator {
    private let discoveryProvider: any RepoScanner.GitRepositoryDiscoveryProvider

    init(
        discoveryProvider: any RepoScanner.GitRepositoryDiscoveryProvider =
            RepoScannerGitDiscoveryClient()
    ) {
        self.discoveryProvider = discoveryProvider
    }

    /// A single discovery probe per worktree. Only evidence that the exact candidate path is
    /// certainly not a git repository rejects registration. Every other outcome — a probe
    /// timeout, cancellation, or service failure, and worktree-metadata drift such as a
    /// symlinked path variant or a stale main-worktree pointer — registers the worktree
    /// provisionally so the row starts scanning instead of stalling forever. The existing
    /// status backoff and honesty threshold in `GitWorkingDirectoryProjector` surface any real,
    /// persistent failure once the worktree is registered.
    func registrationDecision(
        context: WorktreeFilesystemContext
    ) async -> GitWorktreeRegistrationDecision {
        switch await discoveryProvider.discoveryOutcome(for: context.rootPath) {
        case .validated, .timeout, .cancelled, .failure:
            return .validated
        case .authoritativeNegative(let reason):
            return Self.isCertainNonRepository(reason) ? .authoritativeNegative : .validated
        }
    }

    /// Reasons that are true "this path is not a git repository" evidence from libgit2. All
    /// other authoritative-negative reasons describe worktree metadata drift (canonicalized path
    /// variants, a stale main-worktree pointer, a submodule worktree) rather than repository
    /// absence, and must not reject registration.
    private static func isCertainNonRepository(
        _ reason: GitRepositoryAuthoritativeNegativeReason
    ) -> Bool {
        switch reason {
        case .exactCandidateIsNotRepository, .invalidRepository, .invalidWorktreeRegistration,
            .bareRepository, .notAValidWorktree:
            return true
        case .canonicalPathMismatch, .submoduleWorktree, .mainWorktreeMismatch:
            return false
        }
    }
}
