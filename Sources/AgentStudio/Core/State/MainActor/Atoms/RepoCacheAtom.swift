import Foundation
import Observation

@MainActor
@Observable
final class RepoCacheAtom {
    struct HydrationState {
        let repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        let worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        let pullRequestCountByWorktreeId: [UUID: Int]
        let notificationCountByWorktreeId: [UUID: Int]
        let recentTargets: [RecentWorkspaceTarget]
        let sourceRevision: UInt64
        let lastRebuiltAt: Date?
    }

    private(set) var repoEnrichmentByRepoId: [UUID: RepoEnrichment] = [:]
    private(set) var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:]
    private(set) var pullRequestCountByWorktreeId: [UUID: Int] = [:]
    private(set) var notificationCountByWorktreeId: [UUID: Int] = [:]
    private(set) var recentTargets: [RecentWorkspaceTarget] = []
    private(set) var sourceRevision: UInt64 = 0
    private(set) var lastRebuiltAt: Date?

    func setRepoEnrichment(_ enrichment: RepoEnrichment) {
        repoEnrichmentByRepoId[enrichment.repoId] = enrichment
    }

    func setWorktreeEnrichment(_ enrichment: WorktreeEnrichment) {
        worktreeEnrichmentByWorktreeId[enrichment.worktreeId] = enrichment
    }

    func setPullRequestCount(_ count: Int, for worktreeId: UUID) {
        pullRequestCountByWorktreeId[worktreeId] = count
    }

    func setNotificationCount(_ count: Int, for worktreeId: UUID) {
        notificationCountByWorktreeId[worktreeId] = count
    }

    func recordRecentTarget(_ target: RecentWorkspaceTarget) {
        recentTargets.removeAll { $0.id == target.id }
        recentTargets.insert(target, at: 0)
        if recentTargets.count > 6 {
            recentTargets = Array(recentTargets.prefix(6))
        }
    }

    func removeRecentTarget(_ targetId: String) {
        recentTargets.removeAll { $0.id == targetId }
    }

    func removeWorktree(_ worktreeId: UUID) {
        worktreeEnrichmentByWorktreeId.removeValue(forKey: worktreeId)
        pullRequestCountByWorktreeId.removeValue(forKey: worktreeId)
        notificationCountByWorktreeId.removeValue(forKey: worktreeId)
    }

    func removeRepo(_ repoId: UUID) {
        repoEnrichmentByRepoId.removeValue(forKey: repoId)
        let worktreeIdsToRemove = worktreeEnrichmentByWorktreeId.values
            .filter { $0.repoId == repoId }
            .map(\.worktreeId)
        for worktreeId in worktreeIdsToRemove {
            removeWorktree(worktreeId)
        }
    }

    func markRebuilt(sourceRevision: UInt64, at timestamp: Date = Date()) {
        self.sourceRevision = sourceRevision
        self.lastRebuiltAt = timestamp
    }

    func hydrate(_ state: HydrationState) {
        repoEnrichmentByRepoId = state.repoEnrichmentByRepoId
        worktreeEnrichmentByWorktreeId = state.worktreeEnrichmentByWorktreeId
        pullRequestCountByWorktreeId = state.pullRequestCountByWorktreeId
        notificationCountByWorktreeId = state.notificationCountByWorktreeId
        recentTargets = state.recentTargets
        sourceRevision = state.sourceRevision
        lastRebuiltAt = state.lastRebuiltAt
    }

    func clear() {
        repoEnrichmentByRepoId.removeAll(keepingCapacity: false)
        worktreeEnrichmentByWorktreeId.removeAll(keepingCapacity: false)
        pullRequestCountByWorktreeId.removeAll(keepingCapacity: false)
        notificationCountByWorktreeId.removeAll(keepingCapacity: false)
        recentTargets.removeAll(keepingCapacity: false)
        sourceRevision = 0
        lastRebuiltAt = nil
    }
}
