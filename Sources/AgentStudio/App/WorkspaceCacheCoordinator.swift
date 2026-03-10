import Foundation
import os

@MainActor
final class WorkspaceCacheCoordinator {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceCacheCoordinator")

    private let bus: EventBus<RuntimeEnvelope>
    private let workspaceStore: WorkspaceStore
    private let repoCache: WorkspaceRepoCache
    private let scopeSyncHandler: @Sendable (ScopeChange) async -> Void
    private var consumeTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        workspaceStore: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        scopeSyncHandler: @escaping @Sendable (ScopeChange) async -> Void
    ) {
        self.bus = bus
        self.workspaceStore = workspaceStore
        self.repoCache = repoCache
        self.scopeSyncHandler = scopeSyncHandler
    }

    deinit {
        consumeTask?.cancel()
    }

    func startConsuming() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.bus.subscribe()
            for await envelope in stream {
                if Task.isCancelled { break }
                self.consume(envelope)
            }
        }
    }

    func stopConsuming() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    func consume(_ envelope: RuntimeEnvelope) {
        switch envelope {
        case .system(let systemEnvelope):
            handleTopology(systemEnvelope)
        case .worktree(let worktreeEnvelope):
            handleEnrichment(worktreeEnvelope)
        case .pane:
            return
        }
    }

    func handleTopology(_ envelope: SystemEnvelope) {
        guard case .topology(let topologyEvent) = envelope.event else { return }

        switch topologyEvent {
        case .repoDiscovered(let repoPath, _):
            let incomingStableKey = StableKey.fromPath(repoPath)
            let existingRepo = workspaceStore.repos.first {
                $0.repoPath == repoPath || $0.stableKey == incomingStableKey
            }
            if let repo = existingRepo {
                if repoCache.repoEnrichmentByRepoId[repo.id] == nil {
                    repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
                }
                if workspaceStore.isRepoUnavailable(repo.id) {
                    _ = workspaceStore.reassociateRepo(
                        repo.id,
                        to: repoPath,
                        discoveredWorktrees: repo.worktrees
                    )
                }
            } else {
                let repo = workspaceStore.addRepo(at: repoPath)
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
            }
        case .repoRemoved(let repoPath):
            if let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) {
                workspaceStore.markRepoUnavailable(repo.id)
                let orphanedPaneIds = workspaceStore.orphanPanesForRepo(repo.id)
                if !orphanedPaneIds.isEmpty {
                    Self.logger.info(
                        "Repo removed at path=\(repoPath.path, privacy: .public); orphaned \(orphanedPaneIds.count, privacy: .public) pane(s)"
                    )
                }
                repoCache.removeRepo(repo.id)
                Task { [weak self] in
                    await self?.syncScope(.unregisterForgeRepo(repoId: repo.id))
                }
            }
        case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
            guard let repo = workspaceStore.repos.first(where: { $0.id == repoId }) else {
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
                workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: worktrees)
            }
        case .worktreeUnregistered(let worktreeId, let repoId):
            guard let repo = workspaceStore.repos.first(where: { $0.id == repoId }) else { return }
            let worktrees = repo.worktrees.filter { $0.id != worktreeId }
            workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: worktrees)
            repoCache.removeWorktree(worktreeId)
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
            case .branchChanged(let worktreeId, let repoId, _, let to):
                var enrichment =
                    repoCache.worktreeEnrichmentByWorktreeId[worktreeId]
                    ?? WorktreeEnrichment(
                        worktreeId: worktreeId,
                        repoId: repoId,
                        branch: to
                    )
                enrichment.branch = to
                enrichment.updatedAt = Date()
                repoCache.setWorktreeEnrichment(enrichment)
            case .originChanged(let repoId, _, let to):
                let trimmedOrigin = to.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedOrigin.isEmpty else {
                    Self.logger.error(
                        "Ignoring empty originChanged for repoId=\(repoId.uuidString, privacy: .public); local-only resolution must arrive via originUnavailable"
                    )
                    return
                }
                let upstream: String?
                if case .some(.resolvedRemote(_, let raw, _, _)) = repoCache.repoEnrichmentByRepoId[repoId] {
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
                let repoName = workspaceStore.repos.first(where: { $0.id == repoId })?.name ?? repoId.uuidString
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
                for (worktreeId, enrichment) in repoCache.worktreeEnrichmentByWorktreeId
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
        guard let repo = workspaceStore.repos.first(where: { $0.id == repoId }) else { return }

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
        workspaceStore.removeRepo(repoId)
    }

    func syncScope(_ change: ScopeChange) async {
        await scopeSyncHandler(change)
    }

    @discardableResult
    func reassociateRepo(
        repoId: UUID,
        to newPath: URL,
        discoveredWorktrees: [Worktree]
    ) -> Bool {
        let updated = workspaceStore.reassociateRepo(repoId, to: newPath, discoveredWorktrees: discoveredWorktrees)
        guard updated else { return false }
        return true
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
