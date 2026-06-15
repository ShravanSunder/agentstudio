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

    @ObservationIgnored private let repoEnrichmentMap = AtomEntityMap<UUID, RepoEnrichment>(
        isContentEqual: { lhs, rhs in lhs.hasSameCacheContent(as: rhs) }
    )
    @ObservationIgnored private let worktreeEnrichmentMap = AtomEntityMap<UUID, WorktreeEnrichment>(
        isContentEqual: { lhs, rhs in lhs.hasSameCacheContent(as: rhs) }
    )
    @ObservationIgnored private let pullRequestCountMap = AtomEntityMap<UUID, Int>(
        isContentEqual: ==
    )
    @ObservationIgnored private let cacheRevisionAtom = AtomRevision()
    @ObservationIgnored private let repoEnrichmentRevisionAtom = AtomRevision()
    @ObservationIgnored private let worktreeEnrichmentRevisionAtom = AtomRevision()
    @ObservationIgnored private let pullRequestCountRevisionAtom = AtomRevision()
    private(set) var sourceRevision: UInt64 = 0
    private(set) var lastRebuiltAt: Date?

    var cacheRevision: Int {
        cacheRevisionAtom.value
    }

    var worktreeEnrichmentRevision: Int {
        worktreeEnrichmentRevisionAtom.value
    }

    var repoEnrichmentByRepoId: [UUID: RepoEnrichment] {
        _ = repoEnrichmentRevisionAtom.value
        return repoEnrichmentSnapshot()
    }

    var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] {
        _ = worktreeEnrichmentRevisionAtom.value
        return worktreeEnrichmentSnapshot()
    }

    var pullRequestCountByWorktreeId: [UUID: Int] {
        _ = pullRequestCountRevisionAtom.value
        return pullRequestCountSnapshot()
    }

    var repoEnrichmentStorageSlotCount: Int {
        repoEnrichmentMap.storageSlotCount
    }

    var worktreeEnrichmentStorageSlotCount: Int {
        worktreeEnrichmentMap.storageSlotCount
    }

    var pullRequestCountStorageSlotCount: Int {
        pullRequestCountMap.storageSlotCount
    }

    func repoEnrichment(for repoId: UUID) -> RepoEnrichment? {
        repoEnrichmentMap.value(for: repoId)
    }

    func worktreeEnrichment(for worktreeId: UUID) -> WorktreeEnrichment? {
        worktreeEnrichmentMap.value(for: worktreeId)
    }

    func pullRequestCount(for worktreeId: UUID) -> Int? {
        pullRequestCountMap.value(for: worktreeId)
    }

    func worktreeFacts(for worktreeId: UUID) -> RepoWorktreeCacheFacts? {
        let enrichment = worktreeEnrichmentMap.value(for: worktreeId)
        let pullRequestCount = pullRequestCountMap.value(for: worktreeId)
        if enrichment == nil && pullRequestCount == nil {
            return nil
        }
        return RepoWorktreeCacheFacts(
            enrichment: enrichment,
            pullRequestCount: pullRequestCount
        )
    }

    func repoEnrichmentSnapshot() -> [UUID: RepoEnrichment] {
        repoEnrichmentMap.snapshot()
    }

    func worktreeFactsSnapshot() -> [UUID: RepoWorktreeCacheFacts] {
        let worktreeEnrichmentsByWorktreeId = worktreeEnrichmentSnapshot()
        let pullRequestCountsByWorktreeId = pullRequestCountSnapshot()
        let worktreeIds = Set(worktreeEnrichmentsByWorktreeId.keys).union(pullRequestCountsByWorktreeId.keys)
        return Dictionary(
            uniqueKeysWithValues: worktreeIds.map { worktreeId in
                (
                    worktreeId,
                    RepoWorktreeCacheFacts(
                        enrichment: worktreeEnrichmentsByWorktreeId[worktreeId],
                        pullRequestCount: pullRequestCountsByWorktreeId[worktreeId]
                    )
                )
            }
        )
    }

    func worktreeEnrichmentSnapshot() -> [UUID: WorktreeEnrichment] {
        worktreeEnrichmentMap.snapshot()
    }

    func pullRequestCountSnapshot() -> [UUID: Int] {
        pullRequestCountMap.snapshot()
    }

    func setRepoEnrichment(_ enrichment: RepoEnrichment) {
        mutate { mutation in
            let shouldBumpRevision =
                repoEnrichmentMap.snapshotValue(for: enrichment.repoId)
                .map { !$0.hasSameCacheContent(as: enrichment) } ?? true
            repoEnrichmentMap.setValue(enrichment, for: enrichment.repoId, mutation: mutation)
            if shouldBumpRevision {
                repoEnrichmentRevisionAtom.bump()
            }
        }
    }

    func setWorktreeEnrichment(_ enrichment: WorktreeEnrichment) {
        mutate { mutation in
            let shouldBumpRevision =
                worktreeEnrichmentMap.snapshotValue(for: enrichment.worktreeId)
                .map { !$0.hasSameCacheContent(as: enrichment) } ?? true
            worktreeEnrichmentMap.setValue(enrichment, for: enrichment.worktreeId, mutation: mutation)
            if shouldBumpRevision {
                worktreeEnrichmentRevisionAtom.bump()
            }
        }
    }

    func setPullRequestCount(_ count: Int, for worktreeId: UUID) {
        mutate { mutation in
            let shouldBumpRevision = pullRequestCountMap.snapshotValue(for: worktreeId) != count
            pullRequestCountMap.setValue(count, for: worktreeId, mutation: mutation)
            if shouldBumpRevision {
                pullRequestCountRevisionAtom.bump()
            }
        }
    }

    func removeWorktree(_ worktreeId: UUID) {
        mutate { mutation in
            let hadWorktreeEnrichment = worktreeEnrichmentMap.snapshotValue(for: worktreeId) != nil
            let hadPullRequestCount = pullRequestCountMap.snapshotValue(for: worktreeId) != nil
            worktreeEnrichmentMap.removeValue(for: worktreeId, mutation: mutation)
            pullRequestCountMap.removeValue(for: worktreeId, mutation: mutation)
            if hadWorktreeEnrichment {
                worktreeEnrichmentRevisionAtom.bump()
            }
            if hadPullRequestCount {
                pullRequestCountRevisionAtom.bump()
            }
        }
    }

    func removeRepo(_ repoId: UUID) {
        let worktreeIdsToRemove = worktreeEnrichmentMap.snapshot().compactMap { worktreeId, enrichment in
            enrichment.repoId == repoId ? worktreeId : nil
        }
        let hadRepoEnrichment = repoEnrichmentMap.snapshotValue(for: repoId) != nil
        let pullRequestIdsToRemove = worktreeIdsToRemove.filter {
            pullRequestCountMap.snapshotValue(for: $0) != nil
        }
        mutate { mutation in
            repoEnrichmentMap.removeValue(for: repoId, mutation: mutation)
            for worktreeId in worktreeIdsToRemove {
                worktreeEnrichmentMap.removeValue(for: worktreeId, mutation: mutation)
                pullRequestCountMap.removeValue(for: worktreeId, mutation: mutation)
            }
            if hadRepoEnrichment {
                repoEnrichmentRevisionAtom.bump()
            }
            if !worktreeIdsToRemove.isEmpty {
                worktreeEnrichmentRevisionAtom.bump()
            }
            if !pullRequestIdsToRemove.isEmpty {
                pullRequestCountRevisionAtom.bump()
            }
        }
    }

    @discardableResult
    func pruneNilSlots(validRepoIds: Set<UUID>, validWorktreeIds: Set<UUID>) -> Bool {
        let prunedRepoSlots = repoEnrichmentMap.pruneNilSlots(excluding: validRepoIds)
        let prunedWorktreeSlots = worktreeEnrichmentMap.pruneNilSlots(excluding: validWorktreeIds)
        let prunedPullRequestSlots = pullRequestCountMap.pruneNilSlots(excluding: validWorktreeIds)
        return prunedRepoSlots > 0 || prunedWorktreeSlots > 0 || prunedPullRequestSlots > 0
    }

    func markRebuilt(sourceRevision: UInt64, at timestamp: Date = Date()) {
        guard self.sourceRevision != sourceRevision || lastRebuiltAt != timestamp else { return }
        mutate { mutation in
            self.sourceRevision = sourceRevision
            self.lastRebuiltAt = timestamp
            mutation.recordAcceptedChange()
        }
    }

    func hydrate(_ state: HydrationState) {
        let shouldBumpRepoRevision = !Self.repoEnrichmentSnapshotsMatch(
            repoEnrichmentMap.snapshot(),
            state.repoEnrichmentByRepoId
        )
        let shouldBumpWorktreeRevision = !Self.worktreeEnrichmentSnapshotsMatch(
            worktreeEnrichmentMap.snapshot(),
            state.worktreeEnrichmentByWorktreeId
        )
        let shouldBumpPullRequestRevision = pullRequestCountMap.snapshot() != state.pullRequestCountByWorktreeId
        mutate { mutation in
            repoEnrichmentMap.replaceAll(state.repoEnrichmentByRepoId, mutation: mutation)
            worktreeEnrichmentMap.replaceAll(state.worktreeEnrichmentByWorktreeId, mutation: mutation)
            pullRequestCountMap.replaceAll(state.pullRequestCountByWorktreeId, mutation: mutation)
            if sourceRevision != state.sourceRevision || lastRebuiltAt != state.lastRebuiltAt {
                sourceRevision = state.sourceRevision
                lastRebuiltAt = state.lastRebuiltAt
                mutation.recordAcceptedChange()
            }
            if shouldBumpRepoRevision {
                repoEnrichmentRevisionAtom.bump()
            }
            if shouldBumpWorktreeRevision {
                worktreeEnrichmentRevisionAtom.bump()
            }
            if shouldBumpPullRequestRevision {
                pullRequestCountRevisionAtom.bump()
            }
        }
    }

    func clear() {
        mutate { mutation in
            let hadRepoEnrichment = !repoEnrichmentMap.snapshot().isEmpty
            let hadWorktreeEnrichment = !worktreeEnrichmentMap.snapshot().isEmpty
            let hadPullRequestCount = !pullRequestCountMap.snapshot().isEmpty
            repoEnrichmentMap.removeAll(mutation: mutation)
            worktreeEnrichmentMap.removeAll(mutation: mutation)
            pullRequestCountMap.removeAll(mutation: mutation)
            if sourceRevision != 0 || lastRebuiltAt != nil {
                sourceRevision = 0
                lastRebuiltAt = nil
                mutation.recordAcceptedChange()
            }
            if hadRepoEnrichment {
                repoEnrichmentRevisionAtom.bump()
            }
            if hadWorktreeEnrichment {
                worktreeEnrichmentRevisionAtom.bump()
            }
            if hadPullRequestCount {
                pullRequestCountRevisionAtom.bump()
            }
        }
    }

    private func mutate(_ apply: (AtomMutationContext) -> Void) {
        let mutation = AtomMutationContext(aggregateRevision: cacheRevisionAtom)
        apply(mutation)
        mutation.commit()
    }

    private static func repoEnrichmentSnapshotsMatch(
        _ lhs: [UUID: RepoEnrichment],
        _ rhs: [UUID: RepoEnrichment]
    ) -> Bool {
        guard Set(lhs.keys) == Set(rhs.keys) else { return false }
        return lhs.allSatisfy { repoId, enrichment in
            guard let otherEnrichment = rhs[repoId] else { return false }
            return enrichment.hasSameCacheContent(as: otherEnrichment)
        }
    }

    private static func worktreeEnrichmentSnapshotsMatch(
        _ lhs: [UUID: WorktreeEnrichment],
        _ rhs: [UUID: WorktreeEnrichment]
    ) -> Bool {
        guard Set(lhs.keys) == Set(rhs.keys) else { return false }
        return lhs.allSatisfy { worktreeId, enrichment in
            guard let otherEnrichment = rhs[worktreeId] else { return false }
            return enrichment.hasSameCacheContent(as: otherEnrichment)
        }
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

    var cacheRevision: Int {
        enrichmentCacheAtom.cacheRevision
    }

    var worktreeEnrichmentRevision: Int {
        enrichmentCacheAtom.worktreeEnrichmentRevision
    }

    func repoEnrichment(for repoId: UUID) -> RepoEnrichment? {
        enrichmentCacheAtom.repoEnrichment(for: repoId)
    }

    func worktreeEnrichment(for worktreeId: UUID) -> WorktreeEnrichment? {
        enrichmentCacheAtom.worktreeEnrichment(for: worktreeId)
    }

    func pullRequestCount(for worktreeId: UUID) -> Int? {
        enrichmentCacheAtom.pullRequestCount(for: worktreeId)
    }

    func worktreeFacts(for worktreeId: UUID) -> RepoWorktreeCacheFacts? {
        enrichmentCacheAtom.worktreeFacts(for: worktreeId)
    }

    func repoEnrichmentSnapshot() -> [UUID: RepoEnrichment] {
        enrichmentCacheAtom.repoEnrichmentSnapshot()
    }

    func worktreeEnrichmentSnapshot() -> [UUID: WorktreeEnrichment] {
        enrichmentCacheAtom.worktreeEnrichmentSnapshot()
    }

    func pullRequestCountSnapshot() -> [UUID: Int] {
        enrichmentCacheAtom.pullRequestCountSnapshot()
    }

    func worktreeFactsSnapshot() -> [UUID: RepoWorktreeCacheFacts] {
        enrichmentCacheAtom.worktreeFactsSnapshot()
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
