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
        var updated = repoEnrichmentByRepoId
        updated[enrichment.repoId] = enrichment
        repoEnrichmentByRepoId = updated
    }

    func setWorktreeEnrichment(_ enrichment: WorktreeEnrichment) {
        var updated = worktreeEnrichmentByWorktreeId
        updated[enrichment.worktreeId] = enrichment
        worktreeEnrichmentByWorktreeId = updated
    }

    func setPullRequestCount(_ count: Int, for worktreeId: UUID) {
        var updated = pullRequestCountByWorktreeId
        updated[worktreeId] = count
        pullRequestCountByWorktreeId = updated
    }

    func setNotificationCount(_ count: Int, for worktreeId: UUID) {
        var updated = notificationCountByWorktreeId
        updated[worktreeId] = count
        notificationCountByWorktreeId = updated
    }

    func recordRecentTarget(_ target: RecentWorkspaceTarget) {
        var updated = recentTargets
        updated.removeAll { $0.id == target.id }
        updated.insert(target, at: 0)
        if updated.count > 6 {
            updated = Array(updated.prefix(6))
        }
        recentTargets = updated
    }

    func removeRecentTarget(_ targetId: String) {
        var updated = recentTargets
        updated.removeAll { $0.id == targetId }
        recentTargets = updated
    }

    func removeWorktree(_ worktreeId: UUID) {
        var worktrees = worktreeEnrichmentByWorktreeId
        worktrees.removeValue(forKey: worktreeId)
        worktreeEnrichmentByWorktreeId = worktrees

        var pullRequests = pullRequestCountByWorktreeId
        pullRequests.removeValue(forKey: worktreeId)
        pullRequestCountByWorktreeId = pullRequests

        var notifications = notificationCountByWorktreeId
        notifications.removeValue(forKey: worktreeId)
        notificationCountByWorktreeId = notifications
    }

    func removeRepo(_ repoId: UUID) {
        var repoEnrichments = repoEnrichmentByRepoId
        repoEnrichments.removeValue(forKey: repoId)
        repoEnrichmentByRepoId = repoEnrichments
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
        repoEnrichmentByRepoId = [:]
        worktreeEnrichmentByWorktreeId = [:]
        pullRequestCountByWorktreeId = [:]
        notificationCountByWorktreeId = [:]
        recentTargets = []
        sourceRevision = 0
        lastRebuiltAt = nil
    }
}
