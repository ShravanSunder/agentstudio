import Foundation
import Observation

/// Rebuildable derived workspace metadata used by sidebar and runtime projections.
@Observable
@MainActor
final class WorkspaceCacheStore {
    private(set) var repoEnrichmentByRepoId: [UUID: RepoEnrichment] = [:]
    private(set) var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:]
    private(set) var pullRequestCountByWorktreeId: [UUID: Int] = [:]
    private(set) var notificationCountByWorktreeId: [UUID: Int] = [:]
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

    func removeRepo(_ repoId: UUID) {
        repoEnrichmentByRepoId.removeValue(forKey: repoId)
        let worktreeIdsToRemove = worktreeEnrichmentByWorktreeId.values
            .filter { $0.repoId == repoId }
            .map(\.worktreeId)
        for worktreeId in worktreeIdsToRemove {
            worktreeEnrichmentByWorktreeId.removeValue(forKey: worktreeId)
            pullRequestCountByWorktreeId.removeValue(forKey: worktreeId)
            notificationCountByWorktreeId.removeValue(forKey: worktreeId)
        }
    }

    func markRebuilt(sourceRevision: UInt64, at timestamp: Date = Date()) {
        self.sourceRevision = sourceRevision
        self.lastRebuiltAt = timestamp
    }

    func clear() {
        repoEnrichmentByRepoId.removeAll(keepingCapacity: false)
        worktreeEnrichmentByWorktreeId.removeAll(keepingCapacity: false)
        pullRequestCountByWorktreeId.removeAll(keepingCapacity: false)
        notificationCountByWorktreeId.removeAll(keepingCapacity: false)
        sourceRevision = 0
        lastRebuiltAt = nil
    }
}
