import Foundation
import Observation

@MainActor
@Observable
final class RepoEnrichmentCacheAtom {
    struct HydrationState {
        let repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        let worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        let pullRequestCountByWorktreeId: [UUID: Int]
        let sourceRevision: UInt64
        let lastRebuiltAt: Date?
    }

    private(set) var repoEnrichmentByRepoId: [UUID: RepoEnrichment] = [:]
    private(set) var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:]
    private(set) var pullRequestCountByWorktreeId: [UUID: Int] = [:]
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

    func removeWorktree(_ worktreeId: UUID) {
        var worktrees = worktreeEnrichmentByWorktreeId
        worktrees.removeValue(forKey: worktreeId)
        worktreeEnrichmentByWorktreeId = worktrees

        var pullRequests = pullRequestCountByWorktreeId
        pullRequests.removeValue(forKey: worktreeId)
        pullRequestCountByWorktreeId = pullRequests
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
        sourceRevision = state.sourceRevision
        lastRebuiltAt = state.lastRebuiltAt
    }

    func clear() {
        repoEnrichmentByRepoId = [:]
        worktreeEnrichmentByWorktreeId = [:]
        pullRequestCountByWorktreeId = [:]
        sourceRevision = 0
        lastRebuiltAt = nil
    }
}

@MainActor
@Observable
final class RecentWorkspaceTargetAtom {
    private static let maximumRecentTargetCount = 15

    private(set) var recentTargets: [RecentWorkspaceTarget] = []

    func recordRecentTarget(_ target: RecentWorkspaceTarget) {
        var updated = recentTargets
        updated.removeAll { $0.id == target.id }
        updated.insert(target, at: 0)
        if updated.count > Self.maximumRecentTargetCount {
            updated = Array(updated.prefix(Self.maximumRecentTargetCount))
        }
        recentTargets = updated
    }

    func removeRecentTarget(_ targetId: String) {
        var updated = recentTargets
        updated.removeAll { $0.id == targetId }
        recentTargets = updated
    }

    func hydrate(recentTargets: [RecentWorkspaceTarget]) {
        self.recentTargets = Array(recentTargets.prefix(Self.maximumRecentTargetCount))
    }

    func clear() {
        recentTargets = []
    }
}

@MainActor
final class RepoCacheAtom {
    struct HydrationState {
        let repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        let worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        let pullRequestCountByWorktreeId: [UUID: Int]
        let recentTargets: [RecentWorkspaceTarget]
        let sourceRevision: UInt64
        let lastRebuiltAt: Date?
    }

    let enrichmentCacheAtom: RepoEnrichmentCacheAtom
    let recentTargetAtom: RecentWorkspaceTargetAtom

    init(
        enrichmentCacheAtom: RepoEnrichmentCacheAtom = .init(),
        recentTargetAtom: RecentWorkspaceTargetAtom = .init()
    ) {
        self.enrichmentCacheAtom = enrichmentCacheAtom
        self.recentTargetAtom = recentTargetAtom
    }

    var repoEnrichmentByRepoId: [UUID: RepoEnrichment] {
        enrichmentCacheAtom.repoEnrichmentByRepoId
    }

    var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] {
        enrichmentCacheAtom.worktreeEnrichmentByWorktreeId
    }

    var pullRequestCountByWorktreeId: [UUID: Int] {
        enrichmentCacheAtom.pullRequestCountByWorktreeId
    }

    var recentTargets: [RecentWorkspaceTarget] {
        recentTargetAtom.recentTargets
    }

    var sourceRevision: UInt64 {
        enrichmentCacheAtom.sourceRevision
    }

    var lastRebuiltAt: Date? {
        enrichmentCacheAtom.lastRebuiltAt
    }

    func setRepoEnrichment(_ enrichment: RepoEnrichment) {
        enrichmentCacheAtom.setRepoEnrichment(enrichment)
    }

    func setWorktreeEnrichment(_ enrichment: WorktreeEnrichment) {
        enrichmentCacheAtom.setWorktreeEnrichment(enrichment)
    }

    func setPullRequestCount(_ count: Int, for worktreeId: UUID) {
        enrichmentCacheAtom.setPullRequestCount(count, for: worktreeId)
    }

    func recordRecentTarget(_ target: RecentWorkspaceTarget) {
        recentTargetAtom.recordRecentTarget(target)
    }

    func removeRecentTarget(_ targetId: String) {
        recentTargetAtom.removeRecentTarget(targetId)
    }

    func removeWorktree(_ worktreeId: UUID) {
        enrichmentCacheAtom.removeWorktree(worktreeId)
    }

    func removeRepo(_ repoId: UUID) {
        enrichmentCacheAtom.removeRepo(repoId)
    }

    func markRebuilt(sourceRevision: UInt64, at timestamp: Date = Date()) {
        enrichmentCacheAtom.markRebuilt(sourceRevision: sourceRevision, at: timestamp)
    }

    func hydrate(_ state: HydrationState) {
        enrichmentCacheAtom.hydrate(
            .init(
                repoEnrichmentByRepoId: state.repoEnrichmentByRepoId,
                worktreeEnrichmentByWorktreeId: state.worktreeEnrichmentByWorktreeId,
                pullRequestCountByWorktreeId: state.pullRequestCountByWorktreeId,
                sourceRevision: state.sourceRevision,
                lastRebuiltAt: state.lastRebuiltAt
            )
        )
        recentTargetAtom.hydrate(recentTargets: state.recentTargets)
    }

    func clear() {
        enrichmentCacheAtom.clear()
        recentTargetAtom.clear()
    }
}
