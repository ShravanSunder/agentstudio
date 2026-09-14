import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

@MainActor
final class WorkspaceCacheCoordinator {
    typealias RetentionScopeRefresh =
        @Sendable ([WatchedPath], [Repo], UInt64, Set<UUID>) async -> [WatchedFolderTopologyReceipt]

    static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceCacheCoordinator")

    private struct PendingWorktreeEnrichment: Sendable {
        enum UpdateKind: Sendable {
            case snapshot
            case branch
        }

        var observationLifetime: RepositoryFactObservationLifetime
        var enrichment: WorktreeEnrichment
        var shouldRefreshTraceIdentity: Bool
        var updateKind: UpdateKind
    }

    private struct PendingRepositoryProjection: Sendable {
        let envelopeSequence: UInt64
        let observationLifetime: RepositoryFactObservationLifetime
        let projection: PullRequestRepositoryProjection
    }

    var isCollectingRetainedLocations = false
    var retentionValidationInFlight = false
    var retentionIsShuttingDown = false
    var retentionMutationWaiters: [CheckedContinuation<Void, Never>] = []
    var deferredTopologyActions: [@MainActor () -> Void] = []
    let retentionNow: @Sendable () async throws -> RepositoryRetentionTime
    let refreshRetentionScopes: RetentionScopeRefresh
    lazy var retentionScheduler = RepositoryRetentionScheduler(clock: ContinuousClock()) { [weak self] in
        await self?.collectRetainedRepositories()
    }

    private let bus: EventBus<RuntimeEnvelope>
    let workspaceStore: WorkspaceStore
    let repoCache: RepoCacheAtom
    private let welcomeAtom: WelcomeAtom
    let topologyEffectHandler: (any TopologyEffectHandler)?
    let topologyPersistence: RepositoryTopologyStore?
    let validateSourceObservations: @Sendable ([WatchedFolderTopologyObservation]) async -> Bool
    private let scopeSyncHandler: @Sendable (ScopeChange) async -> Void
    private let traceIdentityRefreshHandler: (@MainActor @Sendable () -> Void)?
    private let enrichmentApplyTickCadence: Duration
    private let enrichmentApplyDrainBudget: Duration
    private let enrichmentApplyClock: (any Clock<Duration> & Sendable)?
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    var appliedScopeSequences: [FilesystemSourceID: UInt64] = [:]
    private var consumeTask: Task<Void, Never>?
    private var pendingConsumeStartGeneration: UInt64?
    private var nextConsumeStartGeneration: UInt64 = 0
    private var lastAppliedForgeProjectionSequenceByRepoId: [UUID: UInt64] = [:]
    private var repositoryProjectionApplyGovernor:
        BackgroundFactApplyGovernor<
            UUID, PendingRepositoryProjection
        >?

    /// Read-only observability seam: exposes how many repository-projection
    /// facts have been coalesced into the current pending batch since the
    /// last drain. Lets tests wait for an actual coalescing invariant
    /// instead of inferring it from tick-scheduling side effects.
    var pendingRepositoryProjectionSupersessionCount: Int {
        repositoryProjectionApplyGovernor?.supersededSinceLastDrainCount ?? 0
    }

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        workspaceStore: WorkspaceStore,
        repoCache: RepoCacheAtom,
        welcomeAtom: WelcomeAtom = .init(),
        topologyEffectHandler: (any TopologyEffectHandler)? = nil,
        topologyPersistence: RepositoryTopologyStore? = nil,
        retentionNow: @escaping @Sendable () async throws -> RepositoryRetentionTime = {
            try await RepositoryRetentionTime.current()
        },
        refreshRetentionScopes: @escaping RetentionScopeRefresh = { _, _, _, _ in [] },
        validateSourceObservations: @escaping @Sendable ([WatchedFolderTopologyObservation]) async -> Bool = { _ in
            false
        },
        scopeSyncHandler: @escaping @Sendable (ScopeChange) async -> Void,
        traceIdentityRefreshHandler: (@MainActor @Sendable () -> Void)? = nil,
        enrichmentApplyTickCadence: Duration = AppPolicies.BackgroundFactApplyGovernor.tickCadence,
        enrichmentApplyDrainBudget: Duration = AppPolicies.BackgroundFactApplyGovernor.drainBudget,
        enrichmentApplyClock: (any Clock<Duration> & Sendable)? = nil,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.bus = bus
        self.workspaceStore = workspaceStore
        self.repoCache = repoCache
        self.welcomeAtom = welcomeAtom
        self.topologyEffectHandler = topologyEffectHandler
        self.topologyPersistence = topologyPersistence
        self.retentionNow = retentionNow
        self.refreshRetentionScopes = refreshRetentionScopes
        self.validateSourceObservations = validateSourceObservations
        self.scopeSyncHandler = scopeSyncHandler
        self.traceIdentityRefreshHandler = traceIdentityRefreshHandler
        self.enrichmentApplyTickCadence = enrichmentApplyTickCadence
        self.enrichmentApplyDrainBudget = enrichmentApplyDrainBudget
        self.enrichmentApplyClock = enrichmentApplyClock
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    deinit {
        consumeTask?.cancel()
    }

    func startConsuming() async {
        guard consumeTask == nil, pendingConsumeStartGeneration == nil else { return }
        nextConsumeStartGeneration &+= 1
        let startGeneration = nextConsumeStartGeneration
        pendingConsumeStartGeneration = startGeneration
        let subscription = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "WorkspaceCacheCoordinator",
            factInterest: .matching([
                .systemTopology,
                .systemWorkspaceActivity,
                .worktreeGitWorkingDirectory,
                .worktreeForge,
            ])
        )
        guard pendingConsumeStartGeneration == startGeneration else { return }
        pendingConsumeStartGeneration = nil
        let enrichmentApplyGovernor = makeEnrichmentApplyGovernor()
        let repositoryProjectionApplyGovernor = makeRepositoryProjectionApplyGovernor()
        self.repositoryProjectionApplyGovernor = repositoryProjectionApplyGovernor
        enrichmentApplyGovernor.start()
        repositoryProjectionApplyGovernor.start()
        let consumeDirect: @MainActor @Sendable (RuntimeEnvelope) async -> Void = { [weak self] envelope in
            if case .system(let system) = envelope,
                case .topology(.watchedFolderReconciled(let observation)) = system.event
            {
                await self?.consumeWatchedFolderObservation(observation, sequence: system.seq)
            } else {
                self?.consume(envelope)
            }
        }
        // swiftlint:disable:next no_task_detached
        consumeTask = Task.detached {
            for await envelope in subscription {
                if Task.isCancelled { break }
                if case .system(let system) = envelope, case .topology(let topology) = system.event {
                    switch topology {
                    case .worktreeRegistered, .worktreeUnregistered: continue
                    default: break
                    }
                }
                if Self.isCoalescableEnrichment(envelope) {
                    Self.enqueueCoalescedEnrichment(envelope, on: enrichmentApplyGovernor)
                } else if Self.isRepositoryProjection(envelope) {
                    Self.enqueueCoalescedRepositoryProjection(
                        envelope,
                        on: repositoryProjectionApplyGovernor
                    )
                } else {
                    await enrichmentApplyGovernor.flushPending()
                    await repositoryProjectionApplyGovernor.flushPending()
                    await consumeDirect(envelope)
                }
            }
            await enrichmentApplyGovernor.shutdown()
            await repositoryProjectionApplyGovernor.shutdown()
        }
    }

    func stopConsuming() {
        pendingConsumeStartGeneration = nil
        consumeTask?.cancel()
        consumeTask = nil
        repositoryProjectionApplyGovernor = nil
    }

    func shutdown() async {
        retentionIsShuttingDown = true
        if topologyPersistence != nil { await retentionScheduler.shutdown() }
        pendingConsumeStartGeneration = nil
        let activeTask = consumeTask
        consumeTask?.cancel()
        consumeTask = nil
        if let activeTask {
            await activeTask.value
        }
        repositoryProjectionApplyGovernor = nil
    }

    func consume(_ envelope: RuntimeEnvelope) {
        switch envelope {
        case .system(let systemEnvelope):
            handleTopology(systemEnvelope)
            handleWorkspaceActivity(systemEnvelope)
        case .worktree(let worktreeEnvelope):
            handleEnrichment(worktreeEnvelope)
        case .pane:
            return
        }
    }

    private func makeEnrichmentApplyGovernor()
        -> BackgroundFactApplyGovernor<UUID, PendingWorktreeEnrichment>
    {
        let apply: @MainActor @Sendable (UUID, PendingWorktreeEnrichment) -> Void = { [weak self] worktreeId, pending in
            self?.applyCoalescedEnrichment(for: worktreeId, pending: pending)
        }
        if let enrichmentApplyClock {
            return BackgroundFactApplyGovernor(
                tickCadence: enrichmentApplyTickCadence,
                drainBudget: enrichmentApplyDrainBudget,
                clock: enrichmentApplyClock,
                performanceTraceRecorder: performanceTraceRecorder,
                mergeFacts: Self.mergePendingEnrichment,
                apply: apply
            )
        }
        return BackgroundFactApplyGovernor(
            tickCadence: enrichmentApplyTickCadence,
            drainBudget: enrichmentApplyDrainBudget,
            performanceTraceRecorder: performanceTraceRecorder,
            mergeFacts: Self.mergePendingEnrichment,
            apply: apply
        )
    }

    private func makeRepositoryProjectionApplyGovernor()
        -> BackgroundFactApplyGovernor<UUID, PendingRepositoryProjection>
    {
        let apply: @MainActor @Sendable (UUID, PendingRepositoryProjection) -> Void = { [weak self] repoId, pending in
            self?.applyCoalescedRepositoryProjection(for: repoId, pending: pending)
        }
        if let enrichmentApplyClock {
            return BackgroundFactApplyGovernor(
                tickCadence: enrichmentApplyTickCadence,
                drainBudget: enrichmentApplyDrainBudget,
                clock: enrichmentApplyClock,
                performanceTraceRecorder: performanceTraceRecorder,
                mergeFacts: Self.latestRepositoryProjection,
                apply: apply
            )
        }
        return BackgroundFactApplyGovernor(
            tickCadence: enrichmentApplyTickCadence,
            drainBudget: enrichmentApplyDrainBudget,
            performanceTraceRecorder: performanceTraceRecorder,
            mergeFacts: Self.latestRepositoryProjection,
            apply: apply
        )
    }

    nonisolated private static func isCoalescableEnrichment(_ envelope: RuntimeEnvelope) -> Bool {
        guard case .worktree(let worktreeEnvelope) = envelope else { return false }
        guard case .gitWorkingDirectory(let gitEvent) = worktreeEnvelope.event else { return false }
        switch gitEvent {
        case .snapshotChanged, .branchChanged:
            return true
        case .statusOutcome, .originChanged, .originUnavailable, .worktreeDiscovered, .worktreeRemoved, .diffAvailable:
            return false
        }
    }

    nonisolated private static func isRepositoryProjection(_ envelope: RuntimeEnvelope) -> Bool {
        guard case .worktree(let worktreeEnvelope) = envelope,
            case .forge(.pullRequestRepositoryProjectionChanged) = worktreeEnvelope.event
        else { return false }
        return true
    }

    nonisolated private static func enqueueCoalescedEnrichment(
        _ envelope: RuntimeEnvelope,
        on governor: BackgroundFactApplyGovernor<UUID, PendingWorktreeEnrichment>
    ) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard case .gitWorkingDirectory(let gitEvent) = worktreeEnvelope.event else { return }
        switch gitEvent {
        case .snapshotChanged(let snapshot):
            let pending = PendingWorktreeEnrichment(
                observationLifetime: worktreeEnvelope.observationLifetime,
                enrichment: WorktreeEnrichment(
                    worktreeId: snapshot.worktreeId,
                    repoId: snapshot.repoId,
                    branch: snapshot.branch ?? "",
                    snapshot: snapshot
                ),
                shouldRefreshTraceIdentity: true,
                updateKind: .snapshot
            )
            _ = governor.enqueue(pending, for: snapshot.worktreeId)
        case .branchChanged(let worktreeId, let repoId, _, let to):
            let pending = PendingWorktreeEnrichment(
                observationLifetime: worktreeEnvelope.observationLifetime,
                enrichment: WorktreeEnrichment(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    branch: to
                ),
                shouldRefreshTraceIdentity: true,
                updateKind: .branch
            )
            _ = governor.enqueue(pending, for: worktreeId)
        case .statusOutcome, .originChanged, .originUnavailable, .worktreeDiscovered, .worktreeRemoved, .diffAvailable:
            return
        }
    }

    nonisolated private static func mergePendingEnrichment(
        _ older: PendingWorktreeEnrichment,
        _ newer: PendingWorktreeEnrichment
    ) -> PendingWorktreeEnrichment {
        guard older.observationLifetime == newer.observationLifetime else { return newer }
        guard case .branch = newer.updateKind else {
            guard case .branch = older.updateKind, newer.enrichment.branch.isEmpty else {
                return newer
            }
            var enrichment = newer.enrichment
            enrichment.updateBranch(older.enrichment.branch)
            return PendingWorktreeEnrichment(
                observationLifetime: newer.observationLifetime,
                enrichment: enrichment,
                shouldRefreshTraceIdentity: older.shouldRefreshTraceIdentity || newer.shouldRefreshTraceIdentity,
                updateKind: .snapshot
            )
        }
        var enrichment = older.enrichment
        enrichment.updateBranch(newer.enrichment.branch)
        return PendingWorktreeEnrichment(
            observationLifetime: newer.observationLifetime,
            enrichment: enrichment,
            shouldRefreshTraceIdentity: older.shouldRefreshTraceIdentity || newer.shouldRefreshTraceIdentity,
            updateKind: .branch
        )
    }

    nonisolated private static func enqueueCoalescedRepositoryProjection(
        _ envelope: RuntimeEnvelope,
        on governor: BackgroundFactApplyGovernor<UUID, PendingRepositoryProjection>
    ) {
        guard case .worktree(let worktreeEnvelope) = envelope,
            case .forge(
                .pullRequestRepositoryProjectionChanged(let repoId, let projection, _)
            ) = worktreeEnvelope.event
        else { return }
        _ = governor.enqueue(
            PendingRepositoryProjection(
                envelopeSequence: worktreeEnvelope.seq,
                observationLifetime: worktreeEnvelope.observationLifetime,
                projection: projection
            ),
            for: repoId
        )
    }

    nonisolated private static func latestRepositoryProjection(
        _ older: PendingRepositoryProjection,
        _ newer: PendingRepositoryProjection
    ) -> PendingRepositoryProjection {
        newer.envelopeSequence >= older.envelopeSequence ? newer : older
    }

    private func applyCoalescedEnrichment(for worktreeId: UUID, pending: PendingWorktreeEnrichment) {
        guard
            workspaceStore.repositoryTopologyAtom.acceptsObservation(
                pending.observationLifetime, repositoryID: pending.enrichment.repoId, worktreeID: worktreeId
            )
        else { return }
        let enrichment: WorktreeEnrichment
        switch pending.updateKind {
        case .snapshot:
            enrichment = pending.enrichment
        case .branch:
            var cachedEnrichment =
                repoCache.worktreeEnrichment(for: worktreeId)
                ?? pending.enrichment
            cachedEnrichment.updateBranch(pending.enrichment.branch)
            enrichment = cachedEnrichment
        }
        repoCache.setWorktreeEnrichment(enrichment)
        if pending.shouldRefreshTraceIdentity {
            refreshTraceIdentity()
        }
    }

    private func applyCoalescedRepositoryProjection(
        for repoId: UUID,
        pending: PendingRepositoryProjection
    ) {
        guard
            workspaceStore.repositoryTopologyAtom.acceptsObservation(
                pending.observationLifetime, repositoryID: repoId, worktreeID: nil
            )
        else { return }
        guard
            pending.envelopeSequence
                > (lastAppliedForgeProjectionSequenceByRepoId[repoId] ?? 0)
        else { return }
        lastAppliedForgeProjectionSequenceByRepoId[repoId] = pending.envelopeSequence
        repoCache.applyPullRequestRepositoryProjection(
            pending.projection,
            forRepository: repoId
        )
    }

    private func handleWorkspaceActivity(_ envelope: SystemEnvelope) {
        guard case .workspaceActivity(let activityEvent) = envelope.event else { return }

        switch activityEvent {
        case .folderScanFinished(let rootPath, let discoveredRepoCount):
            welcomeAtom.completeFolderScan(
                rootPath: rootPath,
                discoveredRepoCount: discoveredRepoCount
            )
        }
    }

    func handleEnrichment(_ envelope: WorktreeEnvelope) {
        guard
            workspaceStore.repositoryTopologyAtom.acceptsObservation(
                envelope.observationLifetime, repositoryID: envelope.repoId, worktreeID: envelope.worktreeId
            )
        else { return }
        switch envelope.event {
        case .gitWorkingDirectory(let gitEvent):
            switch gitEvent {
            case .statusOutcome(let statusOutcome):
                handleGitStatusOutcome(statusOutcome)
            case .snapshotChanged(let snapshot):
                let enrichment = WorktreeEnrichment(
                    worktreeId: snapshot.worktreeId,
                    repoId: snapshot.repoId,
                    branch: snapshot.branch ?? "",
                    snapshot: snapshot
                )
                repoCache.setWorktreeEnrichment(enrichment)
                refreshTraceIdentity()
            case .branchChanged(let worktreeId, let repoId, _, let to):
                var enrichment =
                    repoCache.worktreeEnrichment(for: worktreeId)
                    ?? WorktreeEnrichment(
                        worktreeId: worktreeId,
                        repoId: repoId,
                        branch: to
                    )
                enrichment.updateBranch(to)
                repoCache.setWorktreeEnrichment(enrichment)
                refreshTraceIdentity()
            case .originChanged(let repoId, _, let to):
                let trimmedOrigin = to.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedOrigin.isEmpty else {
                    Self.logger.error(
                        "Ignoring empty originChanged for repoId=\(repoId.uuidString, privacy: .public); local-only resolution must arrive via originUnavailable"
                    )
                    return
                }
                let upstream: String?
                if case .some(.resolvedRemote(_, let raw, _, _)) = repoCache.repoEnrichment(for: repoId) {
                    upstream = raw.upstream
                } else {
                    upstream = nil
                }
                let enrichment: RepoEnrichment
                if let identity = RemoteIdentityNormalizer.normalize(trimmedOrigin) {
                    enrichment = .resolvedRemote(
                        repoId: repoId,
                        raw: RawRepoOrigin(origin: trimmedOrigin, upstream: upstream),
                        identity: identity,
                        updatedAt: Date()
                    )
                } else {
                    enrichment = .resolvedRemote(
                        repoId: repoId,
                        raw: RawRepoOrigin(origin: trimmedOrigin, upstream: upstream),
                        identity: RepoIdentity(
                            groupKey: "remote:\(trimmedOrigin)",
                            remoteSlug: nil,
                            organizationName: nil,
                            displayName: Self.fallbackDisplayName(for: trimmedOrigin)
                        ),
                        updatedAt: Date()
                    )
                }
                repoCache.setRepoEnrichment(enrichment)
            case .originUnavailable(let repoId):
                let repoName =
                    workspaceStore.repositoryTopologyAtom.repos.first(where: { $0.id == repoId })?.name
                    ?? repoId.uuidString
                repoCache.setRepoEnrichment(
                    .resolvedLocal(
                        repoId: repoId,
                        identity: RemoteIdentityNormalizer.localIdentity(repoName: repoName),
                        updatedAt: Date()
                    )
                )
            case .worktreeDiscovered, .worktreeRemoved, .diffAvailable:
                break
            }
        case .forge(let forgeEvent):
            handleForgeEnrichment(
                forgeEvent, envelopeSequence: envelope.seq, observationLifetime: envelope.observationLifetime)
        case .filesystem, .security:
            break
        }
    }

    private func handleGitStatusOutcome(_ statusOutcome: GitStatusOutcomeFact) {
        switch statusOutcome.outcome {
        case .completed:
            if case .statusUnavailable = repoCache.repoEnrichment(for: statusOutcome.repoId) {
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: statusOutcome.repoId))
            }
        case .timeout, .unavailable:
            guard let reason = statusOutcome.reason,
                statusOutcome.consecutiveFailureCount
                    >= AppPolicies.GitRefresh.statusUnavailableConsecutiveFailureThreshold
            else { break }
            switch repoCache.repoEnrichment(for: statusOutcome.repoId) {
            case .none, .some(.awaitingOrigin):
                repoCache.setRepoEnrichment(
                    .statusUnavailable(repoId: statusOutcome.repoId, reason: reason.rawValue)
                )
            case .some(.statusUnavailable), .some(.resolvedLocal), .some(.resolvedRemote):
                break
            }
        }
    }

    private func handleForgeEnrichment(
        _ forgeEvent: ForgeEvent,
        envelopeSequence: UInt64,
        observationLifetime: RepositoryFactObservationLifetime
    ) {
        switch forgeEvent {
        case .pullRequestRepositoryProjectionChanged(let repoId, let projection, _):
            applyCoalescedRepositoryProjection(
                for: repoId,
                pending: PendingRepositoryProjection(
                    envelopeSequence: envelopeSequence,
                    observationLifetime: observationLifetime,
                    projection: projection
                )
            )
        case .refreshFailed(let repoId, let error):
            Self.logger.error(
                "Forge refresh failed for repoId=\(repoId.uuidString, privacy: .public): \(error, privacy: .public)"
            )
        case .checksUpdated(let repoId, let status):
            Self.logger.debug(
                "Forge checks updated for repoId=\(repoId.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public)"
            )
        case .rateLimited(let repoId, let retryAfterSeconds):
            Self.logger.warning(
                "Forge provider rate limited for repoId=\(repoId.uuidString, privacy: .public); retryAfterSeconds=\(String(describing: retryAfterSeconds), privacy: .public)"
            )
        }
    }

    /// Hard-deletes a repo and all associated cache/forge state.
    /// Called for user-initiated removal (not filesystem disappearance).
    func handleRepoRemoval(repoId: UUID) {
        if isCollectingRetainedLocations {
            deferredTopologyActions.append { [weak self] in self?.handleRepoRemoval(repoId: repoId) }
            return
        }
        guard let repo = workspaceStore.repositoryTopologyAtom.repos.first(where: { $0.id == repoId }) else { return }
        let removalDelta = WorktreeTopologyDelta(
            repoId: repo.id,
            addedWorktreeIds: [],
            removedWorktrees: repo.worktrees.map { RemovedWorktreeEntry(id: $0.id, path: $0.path) },
            preservedWorktreeIds: [],
            didChange: true,
            traceId: nil
        )

        // 1. Prune all worktree-level cache entries for this repo
        for worktree in repo.worktrees {
            repoCache.removeWorktree(worktree.id)
        }

        // 2. Prune repo-level cache
        repoCache.removeRepo(repoId)
        lastAppliedForgeProjectionSequenceByRepoId.removeValue(forKey: repoId)

        // 3. Unregister only the captured observation lifetime.
        let removedLifetime = workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes[repoId]
        Task { [weak self] in
            await self?.syncScope(.unregisterForgeRepo(repoId: repoId, expectedLifetime: removedLifetime))
        }

        // 4. Hard-delete from store (removes from repos array + persistence)
        workspaceStore.mutationCoordinator.removeRepo(repoId)
        topologyEffectHandler?.topologyDidChange(removalDelta)
        refreshTraceIdentity()
    }

    func syncScope(_ change: ScopeChange) async {
        await scopeSyncHandler(change)
    }

    @discardableResult
    func reassociateRepo(
        repoId: UUID,
        to newPath: URL,
        discoveredWorktrees: [Worktree]
    ) async -> RepositoryReassociationResult {
        await waitForRetentionCommit()
        let result = workspaceStore.mutationCoordinator.reassociateRepo(
            repoId,
            to: newPath,
            discoveredWorktrees: discoveredWorktrees
        )
        switch result {
        case .accepted(let acceptance):
            for entry in acceptance.delta.removedWorktrees {
                repoCache.removeWorktree(entry.id)
            }
            topologyEffectHandler?.topologyDidChange(acceptance.delta)
            refreshTraceIdentity()
            return result
        case .rejected:
            return result
        }
    }

    func refreshTraceIdentity() {
        guard let traceIdentityRefreshHandler else { return }
        traceIdentityRefreshHandler()
    }

}

extension WorkspaceCacheCoordinator {
    fileprivate static func fallbackDisplayName(for remote: String) -> String {
        if let parsedURL = URL(string: remote), !parsedURL.lastPathComponent.isEmpty {
            let name = parsedURL.lastPathComponent
            return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
        }

        let cleanedRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = cleanedRemote.split(separator: "/")
        guard let last = components.last else {
            return cleanedRemote.isEmpty ? remote : cleanedRemote
        }
        let name = String(last)
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
