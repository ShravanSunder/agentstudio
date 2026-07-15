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

    private let bus: EventBus<RuntimeEnvelope>
    private let workspaceStore: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let welcomeAtom: WelcomeAtom
    private let topologyEffectHandler: (any TopologyEffectHandler)?
    private let scopeSyncHandler: @Sendable (ScopeChange) async -> Void
    private let traceIdentityRefreshHandler: (@MainActor @Sendable () async -> Void)?
    private var consumeTask: Task<Void, Never>?
    private var traceIdentityRefreshTask: Task<Void, Never>?
    private var traceIdentityRefreshNeedsReplay = false

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        workspaceStore: WorkspaceStore,
        repoCache: RepoCacheAtom,
        welcomeAtom: WelcomeAtom = .init(),
        topologyEffectHandler: (any TopologyEffectHandler)? = nil,
        scopeSyncHandler: @escaping @Sendable (ScopeChange) async -> Void,
        traceIdentityRefreshHandler: (@MainActor @Sendable () async -> Void)? = nil
    ) {
        self.bus = bus
        self.workspaceStore = workspaceStore
        self.repoCache = repoCache
        self.welcomeAtom = welcomeAtom
        self.topologyEffectHandler = topologyEffectHandler
        self.scopeSyncHandler = scopeSyncHandler
        self.traceIdentityRefreshHandler = traceIdentityRefreshHandler
    }

    deinit {
        consumeTask?.cancel()
        traceIdentityRefreshTask?.cancel()
    }

    func startConsuming() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self] in
            guard
                let subscription = await self?.bus.subscribe(
                    policy: .criticalUnbounded,
                    subscriberName: "WorkspaceCacheCoordinator"
                )
            else { return }
            for await envelope in subscription {
                if Task.isCancelled { break }
                self?.consume(envelope)
            }
        }
    }

    func stopConsuming() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    func shutdown() async {
        let activeTask = consumeTask
        let activeTraceIdentityRefreshTask = traceIdentityRefreshTask
        consumeTask?.cancel()
        consumeTask = nil
        traceIdentityRefreshTask?.cancel()
        traceIdentityRefreshTask = nil
        traceIdentityRefreshNeedsReplay = false
        if let activeTask {
            await activeTask.value
        }
        if let activeTraceIdentityRefreshTask {
            await activeTraceIdentityRefreshTask.value
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

    func handleTopology(_ envelope: SystemEnvelope) {
        guard case .topology(let topologyEvent) = envelope.event else { return }

        switch topologyEvent {
        case .repoDiscovered(let repoPath, _, let linkedWorktrees):
            handleRepoDiscovered(
                repoPath: repoPath,
                linkedWorktrees: linkedWorktrees,
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
        eventId: UUID,
        shouldRefreshTraceIdentity: Bool = true,
        shouldApplyTopologyEffects: Bool = true
    ) -> WorktreeTopologyDelta? {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let normalizedRepoPath = repoPath.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedRepoPath)
        let existingRepo = repositoryTopology.repos.first {
            $0.repoPath.standardizedFileURL == normalizedRepoPath || $0.stableKey == incomingStableKey
        }
        let repoId: UUID
        let shouldInitializeRepoEnrichment: Bool
        if let repo = existingRepo {
            repoId = repo.id
            shouldInitializeRepoEnrichment = repoCache.repoEnrichment(for: repo.id) == nil
        } else {
            let repo = repositoryTopology.addRepo(at: normalizedRepoPath)
            repoId = repo.id
            shouldInitializeRepoEnrichment = true
        }

        guard case .scanned(let linkedPaths) = linkedWorktrees else {
            if repositoryTopology.isRepoUnavailable(repoId),
                let repo = repositoryTopology.repo(repoId)
            {
                let reassociation = workspaceStore.mutationCoordinator.reassociateRepo(
                    repoId,
                    to: normalizedRepoPath,
                    discoveredWorktrees: repo.worktrees
                )
                guard case .accepted = reassociation else { return nil }
            }
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
        eventId: UUID
    ) -> ScannedWorktreeDiscoveryResult {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let scannedWorktrees = Self.buildDiscoveredWorktreeList(
            clonePath: normalizedRepoPath,
            linkedPaths: linkedPaths
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

        let reconciliation = repositoryTopology.reconcileScannedWorktrees(
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
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        var topologyDeltas: [WorktreeTopologyDelta] = []
        repositoryTopology.performBatchedTopologyMutation {
            for repository in repositories {
                if let delta = handleRepoDiscovered(
                    repoPath: repository.repoPath,
                    linkedWorktrees: repository.linkedWorktrees,
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

        repositoryTopology.markRepoUnavailable(repo.id)
        let unavailablePathByWorktreeId = Dictionary(
            uniqueKeysWithValues: repo.worktrees.map { ($0.id, $0.path.path) }
        )
        let orphanedPaneIds = workspaceStore.paneAtom.orphanPanes(
            forUnavailableWorktreePathsById: unavailablePathByWorktreeId
        )
        if !orphanedPaneIds.isEmpty {
            Self.logger.info(
                "Repo removed at path=\(repoPath.path, privacy: .public); orphaned \(orphanedPaneIds.count, privacy: .public) pane(s)"
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
            let reconciliation = repositoryTopology.reconcileDiscoveredWorktrees(repo.id, worktrees: worktrees)
            switch reconciliation {
            case .accepted:
                refreshTraceIdentity()
            case .rejected(let rejection):
                Self.logger.error(
                    "Rejecting worktree registration for repoId=\(repo.id.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
                )
            }
        }
    }

    private func handleWorktreeUnregistered(worktreeId: UUID, repoId: UUID) {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        guard let repo = repositoryTopology.repos.first(where: { $0.id == repoId }) else { return }
        let worktrees = repo.worktrees.filter { $0.id != worktreeId }
        let reconciliation = repositoryTopology.reconcileDiscoveredWorktrees(repo.id, worktrees: worktrees)
        switch reconciliation {
        case .accepted:
            repoCache.removeWorktree(worktreeId)
            refreshTraceIdentity()
        case .rejected(let rejection):
            Self.logger.error(
                "Rejecting worktree unregistration for repoId=\(repo.id.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
            )
        }
    }

    private func handleWorkspaceActivity(_ envelope: SystemEnvelope) {
        guard case .workspaceActivity(let activityEvent) = envelope.event else { return }

        switch activityEvent {
        case .recentTargetOpened(let target):
            Self.logger.debug("Recording recent target id=\(target.id, privacy: .public)")
            repoCache.recordRecentTarget(target)
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
                enrichment.branch = to
                enrichment.updatedAt = Date()
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
            switch forgeEvent {
            case .pullRequestCountsChanged(let repoId, let countsByBranch):
                // Branch-to-worktree mapping is resolved through current enrichment branch values.
                for (worktreeId, enrichment) in repoCache.worktreeEnrichmentSnapshot()
                where enrichment.repoId == repoId {
                    if let count = countsByBranch[enrichment.branch] {
                        repoCache.setPullRequestCount(count, for: worktreeId)
                    }
                }
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
                    "Forge provider rate limited for repoId=\(repoId.uuidString, privacy: .public); retryAfterSeconds=\(retryAfterSeconds, privacy: .public)"
                )
            }
        case .filesystem, .security:
            break
        }
    }

    private static func fallbackDisplayName(for remote: String) -> String {
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

    /// Hard-deletes a repo and all associated cache/forge state.
    /// Called for user-initiated removal (not filesystem disappearance).
    func handleRepoRemoval(repoId: UUID) {
        guard let repo = workspaceStore.repositoryTopologyAtom.repos.first(where: { $0.id == repoId }) else { return }

        // 1. Prune all worktree-level cache entries for this repo
        for worktree in repo.worktrees {
            repoCache.removeWorktree(worktree.id)
        }

        // 2. Prune repo-level cache
        repoCache.removeRepo(repoId)

        // 3. Unregister from forge scope
        Task { [weak self] in
            await self?.syncScope(.unregisterForgeRepo(repoId: repoId))
        }

        // 4. Hard-delete from store (removes from repos array + persistence)
        workspaceStore.repositoryTopologyAtom.removeRepo(repoId)
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
        case .accepted:
            refreshTraceIdentity()
            return result
        case .rejected:
            return result
        }
    }

    private func refreshTraceIdentity() {
        guard let traceIdentityRefreshHandler else { return }
        guard traceIdentityRefreshTask == nil else {
            traceIdentityRefreshNeedsReplay = true
            return
        }
        traceIdentityRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await traceIdentityRefreshHandler()
                guard let self else { return }
                guard self.traceIdentityRefreshNeedsReplay else {
                    self.traceIdentityRefreshTask = nil
                    return
                }
                self.traceIdentityRefreshNeedsReplay = false
            }
            self?.traceIdentityRefreshTask = nil
        }
    }

    private static func buildDiscoveredWorktreeList(
        clonePath: URL,
        linkedPaths: [URL]
    ) -> RepositoryScannedWorktrees {
        let normalizedClonePath = clonePath.standardizedFileURL
        let normalizedLinkedPaths = Array(Set(linkedPaths.map(\.standardizedFileURL)))
            .filter { $0 != normalizedClonePath }
            .sorted(by: sortPaths)

        let mainWorktree = RepositoryScannedMainWorktree(
            name: normalizedClonePath.lastPathComponent,
            path: normalizedClonePath
        )
        let linkedWorktrees = normalizedLinkedPaths.map { linkedPath in
            RepositoryScannedLinkedWorktree(
                name: linkedPath.lastPathComponent,
                path: linkedPath
            )
        }
        return RepositoryScannedWorktrees(main: mainWorktree, linked: linkedWorktrees)
    }

    private static func sortPaths(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}

enum ScopeChange: Sendable {
    case registerForgeRepo(repoId: UUID, remote: String)
    case unregisterForgeRepo(repoId: UUID)
    case refreshForgeRepo(repoId: UUID, correlationId: UUID?)
    case updateWatchedFolders(paths: [URL])
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
        case .updateWatchedFolders(let paths):
            return "updateWatchedFolders(count: \(paths.count))"
        }
    }
}
