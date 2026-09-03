import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

@MainActor
protocol TopologyEffectHandler: AnyObject {
    func topologyDidChange(_ delta: WorktreeTopologyDelta)
    func topologyDidChange(_ deltas: [WorktreeTopologyDelta])
}

extension TopologyEffectHandler {
    func topologyDidChange(_ deltas: [WorktreeTopologyDelta]) {
        for delta in deltas {
            topologyDidChange(delta)
        }
    }
}

@MainActor
final class WorkspaceCacheCoordinator {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceCacheCoordinator")

    private struct PendingWorktreeEnrichment: Sendable {
        enum UpdateKind: Sendable {
            case snapshot
            case branch
        }

        var enrichment: WorktreeEnrichment
        var shouldRefreshTraceIdentity: Bool
        var updateKind: UpdateKind
    }

    private struct PendingRepositoryProjection: Sendable {
        let envelopeSequence: UInt64
        let projection: PullRequestRepositoryProjection
    }

    private let bus: EventBus<RuntimeEnvelope>
    private let workspaceStore: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let welcomeAtom: WelcomeAtom
    private let topologyEffectHandler: (any TopologyEffectHandler)?
    private let scopeSyncHandler: @Sendable (ScopeChange) async -> Void
    private let traceIdentityRefreshHandler: (@MainActor @Sendable () -> Void)?
    private let enrichmentApplyTickCadence: Duration
    private let enrichmentApplyDrainBudget: Duration
    private let enrichmentApplyClock: (any Clock<Duration> & Sendable)?
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private var consumeTask: Task<Void, Never>?
    private var pendingConsumeStartGeneration: UInt64?
    private var nextConsumeStartGeneration: UInt64 = 0
    private var lastAppliedForgeProjectionSequenceByRepoId: [UUID: UInt64] = [:]

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        workspaceStore: WorkspaceStore,
        repoCache: RepoCacheAtom,
        welcomeAtom: WelcomeAtom = .init(),
        topologyEffectHandler: (any TopologyEffectHandler)? = nil,
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
        enrichmentApplyGovernor.start()
        repositoryProjectionApplyGovernor.start()
        let consumeDirect: @MainActor @Sendable (RuntimeEnvelope) -> Void = { [weak self] envelope in
            self?.consume(envelope)
        }
        // swiftlint:disable:next no_task_detached
        consumeTask = Task.detached {
            for await envelope in subscription {
                if Task.isCancelled { break }
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
    }

    func shutdown() async {
        pendingConsumeStartGeneration = nil
        let activeTask = consumeTask
        consumeTask?.cancel()
        consumeTask = nil
        if let activeTask {
            await activeTask.value
        }
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
        guard case .branch = newer.updateKind else {
            guard case .branch = older.updateKind, newer.enrichment.branch.isEmpty else {
                return newer
            }
            var enrichment = newer.enrichment
            enrichment.updateBranch(older.enrichment.branch)
            return PendingWorktreeEnrichment(
                enrichment: enrichment,
                shouldRefreshTraceIdentity: older.shouldRefreshTraceIdentity || newer.shouldRefreshTraceIdentity,
                updateKind: .snapshot
            )
        }
        var enrichment = older.enrichment
        enrichment.updateBranch(newer.enrichment.branch)
        return PendingWorktreeEnrichment(
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
            pending.envelopeSequence
                > (lastAppliedForgeProjectionSequenceByRepoId[repoId] ?? 0)
        else { return }
        lastAppliedForgeProjectionSequenceByRepoId[repoId] = pending.envelopeSequence
        repoCache.applyPullRequestRepositoryProjection(
            pending.projection,
            forRepository: repoId
        )
    }

    func handleTopology(_ envelope: SystemEnvelope) {
        guard case .topology(let topologyEvent) = envelope.event else { return }

        switch topologyEvent {
        case .repoDiscovered(let repoPath, _, let linkedWorktrees, let stableIdentity):
            handleRepoDiscovered(
                repoPath: repoPath,
                linkedWorktrees: linkedWorktrees,
                stableIdentity: stableIdentity,
                eventId: envelope.eventId
            )
        case .reposDiscovered(_, let repositories):
            handleReposDiscovered(
                repositories: repositories,
                eventId: envelope.eventId
            )
        case .repoRemoved(let repoPath):
            handleRepoRemoved(repoPath: repoPath)
        case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
            handleWorktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        case .worktreeUnregistered(let worktreeId, let repoId):
            handleWorktreeUnregistered(worktreeId: worktreeId, repoId: repoId)
        }
    }

    @discardableResult
    private func handleRepoDiscovered(
        repoPath: URL,
        linkedWorktrees: LinkedWorktreeInfo,
        stableIdentity: DiscoveredRepoStableIdentity?,
        eventId: UUID,
        shouldRefreshTraceIdentity: Bool = true,
        shouldApplyTopologyEffects: Bool = true
    ) -> WorktreeTopologyDelta? {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let normalizedRepoPath = repoPath.standardizedFileURL
        let preparedStableIdentity =
            stableIdentity
            ?? .prepare(repoPath: normalizedRepoPath, linkedWorktrees: linkedWorktrees)
        let incomingStableKey = preparedStableIdentity.repositoryStableKey
        let existingRepo =
            repositoryTopology.repo(stableKey: incomingStableKey)
            ?? repositoryTopology.repos.first { $0.repoPath.standardizedFileURL == normalizedRepoPath }
        let repoId: UUID
        let shouldInitializeRepoEnrichment: Bool
        if let repo = existingRepo {
            repoId = repo.id
            shouldInitializeRepoEnrichment = repoCache.repoEnrichment(for: repo.id) == nil
        } else {
            let repo = workspaceStore.mutationCoordinator.addRepo(
                at: normalizedRepoPath,
                stableKey: incomingStableKey
            )
            repoId = repo.id
            shouldInitializeRepoEnrichment = true
        }

        guard case .scanned(let linkedPaths) = linkedWorktrees else {
            if shouldInitializeRepoEnrichment {
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
            }
            if shouldRefreshTraceIdentity {
                refreshTraceIdentity()
            }
            return nil
        }
        guard let repo = repositoryTopology.repos.first(where: { $0.id == repoId }) else {
            Self.logger.error(
                "Repo id=\(repoId.uuidString, privacy: .public) not found after creation — store state inconsistency"
            )
            return nil
        }

        let delta: WorktreeTopologyDelta
        switch applyScannedWorktreeDiscovery(
            repo: repo,
            normalizedRepoPath: normalizedRepoPath,
            linkedPaths: linkedPaths,
            stableIdentity: preparedStableIdentity,
            eventId: eventId
        ) {
        case .accepted(let acceptedDelta):
            delta = acceptedDelta
        case .rejected(let rejection):
            Self.logger.error(
                "Rejecting scanned repo discovery for repoId=\(repo.id.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
            )
            return nil
        }
        guard delta.didChange else {
            if shouldInitializeRepoEnrichment {
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
            }
            if shouldRefreshTraceIdentity {
                refreshTraceIdentity()
            }
            return nil
        }

        for entry in delta.removedWorktrees {
            repoCache.removeWorktree(entry.id)
        }
        if !delta.removedWorktrees.isEmpty, topologyEffectHandler == nil {
            Self.logger.warning(
                "Topology delta has \(delta.removedWorktrees.count, privacy: .public) removed worktree(s) but no effect handler — pane orphaning skipped"
            )
        }
        if shouldApplyTopologyEffects {
            topologyEffectHandler?.topologyDidChange(delta)
        }
        if shouldInitializeRepoEnrichment {
            repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        }
        if shouldRefreshTraceIdentity {
            refreshTraceIdentity()
        }
        return delta
    }

    private enum ScannedWorktreeDiscoveryRejection {
        case reconciliation(RepositoryWorktreeReconciliationRejection)
        case reassociation(RepositoryReassociationRejection)
    }

    private enum ScannedWorktreeDiscoveryResult {
        case accepted(WorktreeTopologyDelta)
        case rejected(ScannedWorktreeDiscoveryRejection)
    }

    private func applyScannedWorktreeDiscovery(
        repo: Repo,
        normalizedRepoPath: URL,
        linkedPaths: [URL],
        stableIdentity: DiscoveredRepoStableIdentity,
        eventId: UUID
    ) -> ScannedWorktreeDiscoveryResult {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let scannedWorktrees = Self.buildDiscoveredWorktreeList(
            clonePath: normalizedRepoPath,
            linkedPaths: linkedPaths,
            stableIdentity: stableIdentity
        )
        if repositoryTopology.isRepoUnavailable(repo.id) {
            let reassociation = workspaceStore.mutationCoordinator.reassociateRepo(
                repo.id,
                to: normalizedRepoPath,
                scannedWorktrees: scannedWorktrees,
                traceId: eventId
            )
            switch reassociation {
            case .accepted(let acceptance):
                return .accepted(acceptance.delta)
            case .rejected(let rejection):
                return .rejected(.reassociation(rejection))
            }
        }

        let reconciliation = workspaceStore.mutationCoordinator.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: scannedWorktrees,
            traceId: eventId
        )
        switch reconciliation {
        case .accepted(let acceptance):
            return .accepted(acceptance.delta)
        case .rejected(let rejection):
            return .rejected(.reconciliation(rejection))
        }
    }

    private func handleReposDiscovered(
        repositories: [DiscoveredRepoTopologyInfo],
        eventId: UUID
    ) {
        guard !repositories.isEmpty else { return }
        var topologyDeltas: [WorktreeTopologyDelta] = []
        workspaceStore.mutationCoordinator.performBatchedTopologyMutation {
            for repository in repositories {
                if let delta = handleRepoDiscovered(
                    repoPath: repository.repoPath,
                    linkedWorktrees: repository.linkedWorktrees,
                    stableIdentity: repository.stableIdentity,
                    eventId: eventId,
                    shouldRefreshTraceIdentity: false,
                    shouldApplyTopologyEffects: false
                ) {
                    topologyDeltas.append(delta)
                }
            }
        }
        if !topologyDeltas.isEmpty {
            topologyEffectHandler?.topologyDidChange(topologyDeltas)
        }
        refreshTraceIdentity()
    }

    private func handleRepoRemoved(repoPath: URL) {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let normalizedRepoPath = repoPath.standardizedFileURL
        let removedStableKey = StableKey.fromPath(normalizedRepoPath)
        guard
            let repo = repositoryTopology.repos.first(where: {
                $0.repoPath.standardizedFileURL == normalizedRepoPath || $0.stableKey == removedStableKey
            })
        else { return }

        workspaceStore.mutationCoordinator.markRepoUnavailable(repo.id)
        let clearedPaneIds = Set(
            repo.worktrees.flatMap { worktree in
                workspaceStore.mutationCoordinator.clearPaneAssociations(
                    forRemovedWorktreeID: worktree.id
                )
            }
        )
        for _ in clearedPaneIds {
            performanceTraceRecorder?.recordPaneAssociationOutcome(.topologyRemoved)
        }
        if !clearedPaneIds.isEmpty {
            Self.logger.info(
                "Repo removed at path=\(repoPath.path, privacy: .public); cleared \(clearedPaneIds.count, privacy: .public) pane association(s)"
            )
        }
        repoCache.removeRepo(repo.id)
        refreshTraceIdentity()
        Task { [weak self] in
            await self?.syncScope(.unregisterForgeRepo(repoId: repo.id))
        }
    }

    private func handleWorktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL) {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        guard let repo = repositoryTopology.repos.first(where: { $0.id == repoId }) else {
            Self.logger.debug(
                "Ignoring worktree registration for unknown repoId=\(repoId.uuidString, privacy: .public)"
            )
            return
        }

        var worktrees = repo.worktrees
        if !worktrees.contains(where: { $0.id == worktreeId }) {
            worktrees.append(
                Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: rootPath.lastPathComponent,
                    path: rootPath,
                    isMainWorktree: false
                )
            )
            let reconciliation = workspaceStore.mutationCoordinator.reconcileDiscoveredWorktrees(
                repo.id,
                worktrees: worktrees
            )
            switch reconciliation {
            case .accepted(let acceptance):
                topologyEffectHandler?.topologyDidChange(acceptance.delta)
                refreshTraceIdentity()
            case .rejected(let rejection):
                Self.logger.error(
                    "Rejecting worktree registration for repoId=\(repo.id.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
                )
            }
        }
    }

    private func handleWorktreeUnregistered(worktreeId: UUID, repoId: UUID) {
        let unregistration = workspaceStore.mutationCoordinator.unregisterWorktree(
            worktreeId,
            from: repoId
        )
        switch unregistration {
        case .accepted(let acceptance):
            for entry in acceptance.delta.removedWorktrees {
                repoCache.removeWorktree(entry.id)
            }
            topologyEffectHandler?.topologyDidChange(acceptance.delta)
            refreshTraceIdentity()
        case .rejected(let rejection):
            Self.logger.error(
                "Rejecting worktree unregistration for repoId=\(repoId.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
            )
        }
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
        switch envelope.event {
        case .gitWorkingDirectory(let gitEvent):
            switch gitEvent {
            case .statusOutcome(let statusOutcome):
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
            handleForgeEnrichment(forgeEvent, envelopeSequence: envelope.seq)
        case .filesystem, .security:
            break
        }
    }

    private func handleForgeEnrichment(
        _ forgeEvent: ForgeEvent,
        envelopeSequence: UInt64
    ) {
        switch forgeEvent {
        case .pullRequestRepositoryProjectionChanged(let repoId, let projection, _):
            applyCoalescedRepositoryProjection(
                for: repoId,
                pending: PendingRepositoryProjection(
                    envelopeSequence: envelopeSequence,
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

        // 3. Unregister from forge scope
        Task { [weak self] in
            await self?.syncScope(.unregisterForgeRepo(repoId: repoId))
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
    ) -> RepositoryReassociationResult {
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

    private func refreshTraceIdentity() {
        guard let traceIdentityRefreshHandler else { return }
        traceIdentityRefreshHandler()
    }

    private static func buildDiscoveredWorktreeList(
        clonePath: URL,
        linkedPaths: [URL],
        stableIdentity: DiscoveredRepoStableIdentity
    ) -> RepositoryScannedWorktrees {
        let normalizedClonePath = clonePath.standardizedFileURL
        let normalizedLinkedPaths = Array(Set(linkedPaths.map(\.standardizedFileURL)))
            .filter { $0 != normalizedClonePath }
            .sorted(by: sortPaths)

        let mainWorktree = RepositoryScannedMainWorktree(
            name: normalizedClonePath.lastPathComponent,
            path: normalizedClonePath,
            stableKey: stableIdentity.worktreeStableKeysByPath[normalizedClonePath]
        )
        let linkedWorktrees = normalizedLinkedPaths.map { linkedPath in
            RepositoryScannedLinkedWorktree(
                name: linkedPath.lastPathComponent,
                path: linkedPath,
                stableKey: stableIdentity.worktreeStableKeysByPath[linkedPath]
            )
        }
        return RepositoryScannedWorktrees(main: mainWorktree, linked: linkedWorktrees)
    }

    private static func sortPaths(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
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

enum ScopeChange: Sendable {
    case registerForgeRepo(repoId: UUID, remote: String)
    case unregisterForgeRepo(repoId: UUID)
    case refreshForgeRepo(repoId: UUID, correlationId: UUID?)
    case updateWatchedFolders(watchedPaths: [WatchedPath])
}

extension ScopeChange: CustomStringConvertible {
    var description: String {
        switch self {
        case .registerForgeRepo(let repoId, let remote):
            return "registerForgeRepo(repoId: \(repoId.uuidString), remote: \(remote))"
        case .unregisterForgeRepo(let repoId):
            return "unregisterForgeRepo(repoId: \(repoId.uuidString))"
        case .refreshForgeRepo(let repoId, let correlationId):
            return
                "refreshForgeRepo(repoId: \(repoId.uuidString), correlationId: \(correlationId?.uuidString ?? "nil"))"
        case .updateWatchedFolders(let watchedPaths):
            return "updateWatchedFolders(count: \(watchedPaths.count))"
        }
    }
}
