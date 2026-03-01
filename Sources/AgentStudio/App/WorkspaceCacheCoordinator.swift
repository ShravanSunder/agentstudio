import Foundation
import os

@MainActor
final class WorkspaceCacheCoordinator {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceCacheCoordinator")

    private let bus: EventBus<RuntimeEnvelope>
    private let workspaceStore: WorkspaceStore
    private let cacheStore: WorkspaceCacheStore
    private let scopeSyncHandler: (@Sendable (ScopeChange) async -> Void)?
    private var consumeTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        workspaceStore: WorkspaceStore,
        cacheStore: WorkspaceCacheStore,
        scopeSyncHandler: (@Sendable (ScopeChange) async -> Void)? = nil
    ) {
        self.bus = bus
        self.workspaceStore = workspaceStore
        self.cacheStore = cacheStore
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
            let exists = workspaceStore.repos.contains { $0.repoPath == repoPath }
            if !exists {
                _ = workspaceStore.addRepo(at: repoPath)
            } else if let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) {
                if workspaceStore.isRepoUnavailable(repo.id) {
                    _ = workspaceStore.reassociateRepo(
                        repo.id,
                        to: repoPath,
                        discoveredWorktrees: repo.worktrees
                    )
                }
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
                cacheStore.removeRepo(repo.id)
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
                        name: rootPath.lastPathComponent,
                        path: rootPath,
                        branch: "",
                        status: .idle,
                        isMainWorktree: false
                    )
                )
                workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: worktrees)
            }
        case .worktreeUnregistered(let worktreeId, let repoId):
            guard let repo = workspaceStore.repos.first(where: { $0.id == repoId }) else { return }
            let worktrees = repo.worktrees.filter { $0.id != worktreeId }
            workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: worktrees)
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
                cacheStore.setWorktreeEnrichment(enrichment)
            case .branchChanged(let worktreeId, let repoId, _, let to):
                var enrichment =
                    cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]
                    ?? WorktreeEnrichment(
                        worktreeId: worktreeId,
                        repoId: repoId,
                        branch: to
                    )
                enrichment.branch = to
                enrichment.updatedAt = Date()
                cacheStore.setWorktreeEnrichment(enrichment)
                Task { [weak self] in
                    await self?.syncScope(
                        .refreshForgeRepo(repoId: repoId, correlationId: envelope.correlationId)
                    )
                }
            case .originChanged(let repoId, _, let to):
                var existing = cacheStore.repoEnrichmentByRepoId[repoId] ?? RepoEnrichment(repoId: repoId)
                existing.origin = to
                cacheStore.setRepoEnrichment(existing)
                Task { [weak self] in
                    guard let self else { return }
                    if to.isEmpty {
                        await self.syncScope(.unregisterForgeRepo(repoId: repoId))
                    } else {
                        await self.syncScope(.registerForgeRepo(repoId: repoId, remote: to))
                    }
                }
            case .worktreeDiscovered, .worktreeRemoved, .diffAvailable:
                break
            }
        case .forge(let forgeEvent):
            switch forgeEvent {
            case .pullRequestCountsChanged(_, let countsByBranch):
                // Branch-to-worktree mapping is resolved through current enrichment branch values.
                for (worktreeId, enrichment) in cacheStore.worktreeEnrichmentByWorktreeId {
                    if let count = countsByBranch[enrichment.branch] {
                        cacheStore.setPullRequestCount(count, for: worktreeId)
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

    func syncScope(_ change: ScopeChange) async {
        guard let scopeSyncHandler else {
            Self.logger.warning(
                "Scope change dropped because no sync handler is configured: \(String(describing: change), privacy: .public)"
            )
            return
        }
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
        }
    }
}
