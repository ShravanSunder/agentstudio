import Foundation
import os

@MainActor
final class WorkspaceCacheCoordinator {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceCacheCoordinator")

    private let bus: EventBus<RuntimeEnvelope>
    private let workspaceStore: WorkspaceStore
    private let cacheStore: WorkspaceCacheStore
    private var consumeTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        workspaceStore: WorkspaceStore,
        cacheStore: WorkspaceCacheStore
    ) {
        self.bus = bus
        self.workspaceStore = workspaceStore
        self.cacheStore = cacheStore
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
            }
        case .repoRemoved(let repoPath):
            if let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) {
                workspaceStore.removeRepo(repo.id)
                cacheStore.removeRepo(repo.id)
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
                let enrichment = WorktreeEnrichment(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    branch: to
                )
                cacheStore.setWorktreeEnrichment(enrichment)
            case .originChanged(let repoId, _, let to):
                var existing = cacheStore.repoEnrichmentByRepoId[repoId] ?? RepoEnrichment(repoId: repoId)
                existing.origin = to
                cacheStore.setRepoEnrichment(existing)
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
            case .refreshFailed, .checksUpdated, .rateLimited:
                break
            }
        case .filesystem, .security:
            break
        }
    }

    func syncScope(_ change: ScopeChange) async {
        _ = change
        // Scope synchronization is wired when FilesystemActor/ForgeActor orchestration lands.
    }
}

enum ScopeChange: Sendable {
    case repoDiscovered(repoId: UUID)
    case repoRemoved(repoId: UUID)
    case worktreeRegistered(worktreeId: UUID)
    case worktreeUnregistered(worktreeId: UUID)
}
