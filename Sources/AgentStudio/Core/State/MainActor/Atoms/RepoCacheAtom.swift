import AgentStudioInfrastructure
import Foundation
import Observation

@MainActor
@Observable
package final class RepoEnrichmentCacheAtom {
    struct HydrationState {
        let repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        let worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        let sourceRevision: UInt64
        let lastRebuiltAt: Date?
    }

    @ObservationIgnored private let repoEnrichmentMap = AtomFamily<UUID, RepoEnrichment>(
        telemetryLabel: "repo_enrichment",
        isContentEqual: { lhs, rhs in lhs.hasSameCacheContent(as: rhs) }
    )
    @ObservationIgnored private let worktreeEnrichmentMap = AtomFamily<UUID, WorktreeEnrichment>(
        telemetryLabel: "worktree_enrichment",
        isContentEqual: { lhs, rhs in lhs.hasSameCacheContent(as: rhs) }
    )
    @ObservationIgnored private let pullRequestFactsMap = AtomFamily<RepoBranchKey, PullRequestFacts>(
        telemetryLabel: "pull_request_facts",
        isContentEqual: ==
    )
    @ObservationIgnored private let pullRequestLoadingMap = AtomFamily<UUID, Bool>(
        telemetryLabel: "pull_request_loading",
        isContentEqual: ==
    )
    @ObservationIgnored private let cacheRevisionAtom = AtomRevision()
    @ObservationIgnored private let repoEnrichmentRevisionAtom = AtomRevision()
    @ObservationIgnored private let worktreeEnrichmentRevisionAtom = AtomRevision()
    @ObservationIgnored private let pullRequestFactsRevisionAtom = AtomRevision()
    /// Repositories whose pull request data is terminally unresolved (no
    /// GitHub remote, or provider queries have failed past the forge honesty
    /// threshold). Gated on its own revision atom, independent from
    /// `pullRequestFactsRevisionAtom`, so a fact write for one repository
    /// does not coarsely wake every reader of this set — only a change to
    /// the unavailable membership itself does.
    @ObservationIgnored private var pullRequestUnavailableRepoIds: Set<UUID> = []
    @ObservationIgnored private let pullRequestUnavailabilityRevisionAtom = AtomRevision()
    private(set) var sourceRevision: UInt64 = 0
    private(set) var lastRebuiltAt: Date?

    var cacheRevision: Int {
        cacheRevisionAtom.value
    }

    var worktreeEnrichmentRevision: Int {
        worktreeEnrichmentRevisionAtom.value
    }

    var repoEnrichmentRevision: Int {
        repoEnrichmentRevisionAtom.value
    }

    var repoEnrichmentByRepoId: [UUID: RepoEnrichment] {
        _ = repoEnrichmentRevisionAtom.value
        return repoEnrichmentSnapshot()
    }

    var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] {
        _ = worktreeEnrichmentRevisionAtom.value
        return worktreeEnrichmentSnapshot()
    }

    package var pullRequestFactsByBranch: [RepoBranchKey: PullRequestFacts] {
        _ = pullRequestFactsRevisionAtom.value
        return pullRequestFactsSnapshot()
    }

    package var unavailablePullRequestRepoIds: Set<UUID> {
        _ = pullRequestUnavailabilityRevisionAtom.value
        return pullRequestUnavailableRepoIds
    }

    package var loadingPullRequestRepoIds: Set<UUID> {
        Set(pullRequestLoadingMap.snapshot().compactMap { repoId, isLoading in isLoading ? repoId : nil })
    }

    var repoEnrichmentStorageSlotCount: Int {
        repoEnrichmentMap.storageSlotCount
    }

    var worktreeEnrichmentStorageSlotCount: Int {
        worktreeEnrichmentMap.storageSlotCount
    }

    var pullRequestFactsStorageSlotCount: Int {
        pullRequestFactsMap.storageSlotCount
    }

    package func repoEnrichment(for repoId: UUID) -> RepoEnrichment? {
        repoEnrichmentMap.value(for: repoId)
    }

    package func worktreeEnrichment(for worktreeId: UUID) -> WorktreeEnrichment? {
        worktreeEnrichmentMap.value(for: worktreeId)
    }

    package func pullRequestFacts(for key: RepoBranchKey) -> PullRequestFacts? {
        pullRequestFactsMap.value(for: key)
    }

    package func isPullRequestDataUnavailable(forRepository repoId: UUID) -> Bool {
        _ = pullRequestUnavailabilityRevisionAtom.value
        return pullRequestUnavailableRepoIds.contains(repoId)
    }

    package func isPullRequestLoading(forRepository repoId: UUID) -> Bool {
        pullRequestLoadingMap.value(for: repoId) ?? false
    }

    func repoEnrichmentSnapshot() -> [UUID: RepoEnrichment] {
        repoEnrichmentMap.snapshot()
    }

    func worktreeEnrichmentSnapshot() -> [UUID: WorktreeEnrichment] {
        worktreeEnrichmentMap.snapshot()
    }

    package func pullRequestFactsSnapshot() -> [RepoBranchKey: PullRequestFacts] {
        pullRequestFactsMap.snapshot()
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

    package func applyPullRequestFacts(_ factsByKey: [RepoBranchKey: PullRequestFacts]) {
        mutate { mutation in
            var didChangeContent = false
            for (key, facts) in factsByKey {
                if pullRequestFactsMap.snapshotValue(for: key) != facts {
                    didChangeContent = true
                }
                pullRequestFactsMap.setValue(facts, for: key, mutation: mutation)
            }
            if didChangeContent {
                pullRequestFactsRevisionAtom.bump()
            }
        }
        // Real facts arrived, so this repository is demonstrably resolvable;
        // an earlier terminal-unavailable marker no longer applies.
        for repoId in Set(factsByKey.keys.map(\.repoId)) {
            clearPullRequestsUnavailable(forRepository: repoId)
        }
    }

    package func setPullRequestLoading(_ isLoading: Bool, forRepository repoId: UUID) {
        mutate { mutation in
            if isLoading {
                pullRequestLoadingMap.setValue(true, for: repoId, mutation: mutation)
            } else {
                pullRequestLoadingMap.removeValue(for: repoId, mutation: mutation)
            }
        }
    }

    package func removePullRequestFacts(keys: Set<RepoBranchKey>) {
        removePullRequestFactKeys(keys)
    }

    package func removePullRequestFacts(forRepository repoId: UUID) {
        let keys = pullRequestFactsMap.snapshot().keys.filter { $0.repoId == repoId }
        removePullRequestFactKeys(keys)
        clearPullRequestsUnavailable(forRepository: repoId)
        setPullRequestLoading(false, forRepository: repoId)
    }

    /// Marks a repository's pull request data as terminally unresolved (no
    /// GitHub remote, or provider queries have failed past the forge honesty
    /// threshold) and discards any stale facts, so the sidebar renders
    /// neither a pending glyph nor a chip for this repository until a fresh
    /// origin or a successful query clears the marker.
    package func markPullRequestsUnavailable(forRepository repoId: UUID) {
        setPullRequestLoading(false, forRepository: repoId)
        mutate { mutation in
            let staleFactKeys = pullRequestFactsMap.snapshot().keys.filter { $0.repoId == repoId }
            for key in staleFactKeys {
                pullRequestFactsMap.removeValue(for: key, mutation: mutation)
            }
            let didInsert = pullRequestUnavailableRepoIds.insert(repoId).inserted
            if didInsert || !staleFactKeys.isEmpty {
                mutation.recordAcceptedChange()
            }
            if !staleFactKeys.isEmpty {
                pullRequestFactsRevisionAtom.bump()
            }
            if didInsert {
                pullRequestUnavailabilityRevisionAtom.bump()
            }
        }
    }

    /// Clears a terminal-unavailable marker, returning the repository to the
    /// pending state so the next successful forge query can resolve real
    /// facts.
    package func clearPullRequestsUnavailable(forRepository repoId: UUID) {
        guard pullRequestUnavailableRepoIds.remove(repoId) != nil else { return }
        mutate { mutation in
            mutation.recordAcceptedChange()
            pullRequestUnavailabilityRevisionAtom.bump()
        }
    }

    func removeWorktree(_ worktreeId: UUID) {
        mutate { mutation in
            let hadWorktreeEnrichment = worktreeEnrichmentMap.snapshotValue(for: worktreeId) != nil
            worktreeEnrichmentMap.removeValue(for: worktreeId, mutation: mutation)
            if hadWorktreeEnrichment {
                worktreeEnrichmentRevisionAtom.bump()
            }
        }
    }

    func removeRepo(_ repoId: UUID) {
        let worktreeIdsToRemove = worktreeEnrichmentMap.snapshot().compactMap { worktreeId, enrichment in
            enrichment.repoId == repoId ? worktreeId : nil
        }
        let hadRepoEnrichment = repoEnrichmentMap.snapshotValue(for: repoId) != nil
        mutate { mutation in
            repoEnrichmentMap.removeValue(for: repoId, mutation: mutation)
            for worktreeId in worktreeIdsToRemove {
                worktreeEnrichmentMap.removeValue(for: worktreeId, mutation: mutation)
            }
            if hadRepoEnrichment {
                repoEnrichmentRevisionAtom.bump()
            }
            if !worktreeIdsToRemove.isEmpty {
                worktreeEnrichmentRevisionAtom.bump()
            }
        }
        removePullRequestFacts(forRepository: repoId)
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
        mutate { mutation in
            repoEnrichmentMap.replaceAll(state.repoEnrichmentByRepoId, mutation: mutation)
            worktreeEnrichmentMap.replaceAll(state.worktreeEnrichmentByWorktreeId, mutation: mutation)
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
        }
    }

    func clear() {
        mutate { mutation in
            let hadRepoEnrichment = !repoEnrichmentMap.snapshot().isEmpty
            let hadWorktreeEnrichment = !worktreeEnrichmentMap.snapshot().isEmpty
            let hadPullRequestFacts = !pullRequestFactsMap.snapshot().isEmpty
            let hadPullRequestLoading = !pullRequestLoadingMap.snapshot().isEmpty
            let hadUnavailablePullRequestRepoIds = !pullRequestUnavailableRepoIds.isEmpty
            repoEnrichmentMap.removeAll(mutation: mutation)
            worktreeEnrichmentMap.removeAll(mutation: mutation)
            pullRequestFactsMap.removeAll(mutation: mutation)
            pullRequestLoadingMap.removeAll(mutation: mutation)
            pullRequestUnavailableRepoIds.removeAll(keepingCapacity: false)
            if sourceRevision != 0 || lastRebuiltAt != nil {
                sourceRevision = 0
                lastRebuiltAt = nil
                mutation.recordAcceptedChange()
            }
            if hadUnavailablePullRequestRepoIds {
                mutation.recordAcceptedChange()
            }
            if hadRepoEnrichment {
                repoEnrichmentRevisionAtom.bump()
            }
            if hadWorktreeEnrichment {
                worktreeEnrichmentRevisionAtom.bump()
            }
            if hadPullRequestFacts {
                pullRequestFactsRevisionAtom.bump()
            }
            if hadPullRequestLoading {
                mutation.recordAcceptedChange()
            }
            if hadUnavailablePullRequestRepoIds {
                pullRequestUnavailabilityRevisionAtom.bump()
            }
        }
    }

    private func mutate(_ apply: (AtomMutationContext) -> Void) {
        let mutation = AtomMutationContext(aggregateRevision: cacheRevisionAtom)
        apply(mutation)
        mutation.commit()
    }

    private func removePullRequestFactKeys<S: Sequence>(_ keys: S) where S.Element == RepoBranchKey {
        let existingKeys = keys.filter { pullRequestFactsMap.snapshotValue(for: $0) != nil }
        guard !existingKeys.isEmpty else { return }
        mutate { mutation in
            for key in existingKeys {
                pullRequestFactsMap.removeValue(for: key, mutation: mutation)
            }
            pullRequestFactsRevisionAtom.bump()
        }
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
package final class RepoCacheAtom {
    struct HydrationState {
        let repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        let worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        let sourceRevision: UInt64
        let lastRebuiltAt: Date?
    }

    package let enrichmentCacheAtom: RepoEnrichmentCacheAtom

    package init(
        enrichmentCacheAtom: RepoEnrichmentCacheAtom = .init()
    ) {
        self.enrichmentCacheAtom = enrichmentCacheAtom
    }

    var repoEnrichmentByRepoId: [UUID: RepoEnrichment] {
        enrichmentCacheAtom.repoEnrichmentByRepoId
    }

    var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] {
        enrichmentCacheAtom.worktreeEnrichmentByWorktreeId
    }

    package var pullRequestFactsByBranch: [RepoBranchKey: PullRequestFacts] {
        enrichmentCacheAtom.pullRequestFactsByBranch
    }

    package var unavailablePullRequestRepoIds: Set<UUID> {
        enrichmentCacheAtom.unavailablePullRequestRepoIds
    }

    package var loadingPullRequestRepoIds: Set<UUID> {
        enrichmentCacheAtom.loadingPullRequestRepoIds
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

    package var repoEnrichmentRevision: Int {
        enrichmentCacheAtom.repoEnrichmentRevision
    }

    package func repoEnrichment(for repoId: UUID) -> RepoEnrichment? {
        enrichmentCacheAtom.repoEnrichment(for: repoId)
    }

    package func worktreeEnrichment(for worktreeId: UUID) -> WorktreeEnrichment? {
        enrichmentCacheAtom.worktreeEnrichment(for: worktreeId)
    }

    package func pullRequestFacts(for key: RepoBranchKey) -> PullRequestFacts? {
        enrichmentCacheAtom.pullRequestFacts(for: key)
    }

    package func isPullRequestDataUnavailable(forRepository repoId: UUID) -> Bool {
        enrichmentCacheAtom.isPullRequestDataUnavailable(forRepository: repoId)
    }

    package func isPullRequestLoading(forRepository repoId: UUID) -> Bool {
        enrichmentCacheAtom.isPullRequestLoading(forRepository: repoId)
    }

    package func repoEnrichmentSnapshot() -> [UUID: RepoEnrichment] {
        enrichmentCacheAtom.repoEnrichmentSnapshot()
    }

    package func worktreeEnrichmentSnapshot() -> [UUID: WorktreeEnrichment] {
        enrichmentCacheAtom.worktreeEnrichmentSnapshot()
    }

    package func pullRequestFactsSnapshot() -> [RepoBranchKey: PullRequestFacts] {
        enrichmentCacheAtom.pullRequestFactsSnapshot()
    }

    package func setRepoEnrichment(_ enrichment: RepoEnrichment) {
        enrichmentCacheAtom.setRepoEnrichment(enrichment)
    }

    package func setWorktreeEnrichment(_ enrichment: WorktreeEnrichment) {
        enrichmentCacheAtom.setWorktreeEnrichment(enrichment)
    }

    package func applyPullRequestFacts(_ factsByKey: [RepoBranchKey: PullRequestFacts]) {
        enrichmentCacheAtom.applyPullRequestFacts(factsByKey)
    }

    package func setPullRequestLoading(_ isLoading: Bool, forRepository repoId: UUID) {
        enrichmentCacheAtom.setPullRequestLoading(isLoading, forRepository: repoId)
    }

    package func removePullRequestFacts(keys: Set<RepoBranchKey>) {
        enrichmentCacheAtom.removePullRequestFacts(keys: keys)
    }

    package func removePullRequestFacts(forRepository repoId: UUID) {
        enrichmentCacheAtom.removePullRequestFacts(forRepository: repoId)
    }

    package func markPullRequestsUnavailable(forRepository repoId: UUID) {
        enrichmentCacheAtom.markPullRequestsUnavailable(forRepository: repoId)
    }

    package func clearPullRequestsUnavailable(forRepository repoId: UUID) {
        enrichmentCacheAtom.clearPullRequestsUnavailable(forRepository: repoId)
    }

    package func removeWorktree(_ worktreeId: UUID) {
        enrichmentCacheAtom.removeWorktree(worktreeId)
    }

    package func removeRepo(_ repoId: UUID) {
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
                sourceRevision: state.sourceRevision,
                lastRebuiltAt: state.lastRebuiltAt
            )
        )
    }

    func clear() {
        enrichmentCacheAtom.clear()
    }
}
