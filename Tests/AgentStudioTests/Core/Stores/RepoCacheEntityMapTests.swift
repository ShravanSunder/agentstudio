import Foundation
import Observation
import Testing

@testable import AgentStudio

private final class RepoCacheEntityMapInvalidationCounter: @unchecked Sendable {
    var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
@Suite(.serialized)
struct RepoCacheEntityMapTests {
    @Test
    func repoEnrichmentKeyReadInvalidatesOnlyMatchingRepo() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let watchedRepoId = UUID()
        let unrelatedRepoId = UUID()
        let invalidationCounter = RepoCacheEntityMapInvalidationCounter()

        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: watchedRepoId))
        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: unrelatedRepoId))

        withObservationTracking {
            _ = cacheAtom.repoEnrichment(for: watchedRepoId)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.setRepoEnrichment(Self.localRepoEnrichment(repoId: unrelatedRepoId, displayName: "other"))

        #expect(!invalidationCounter.didFire)

        cacheAtom.setRepoEnrichment(Self.localRepoEnrichment(repoId: watchedRepoId, displayName: "watched"))

        #expect(invalidationCounter.count == 1)
        #expect(cacheAtom.repoEnrichment(for: watchedRepoId)?.displayName == "watched")
    }

    @Test
    func worktreeFactsKeyReadCombinesEnrichmentAndPullRequestCount() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()

        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )
        cacheAtom.setPullRequestCount(3, for: worktreeId)

        let facts = cacheAtom.worktreeFacts(for: worktreeId)

        #expect(facts?.enrichment?.branch == "main")
        #expect(facts?.pullRequestCount == 3)
    }

    @Test
    func worktreeFactsMutationsPreserveOtherSource() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()

        cacheAtom.setPullRequestCount(2, for: worktreeId)
        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )

        #expect(cacheAtom.worktreeFacts(for: worktreeId)?.pullRequestCount == 2)

        cacheAtom.setPullRequestCount(5, for: worktreeId)

        #expect(cacheAtom.worktreeFacts(for: worktreeId)?.enrichment?.branch == "main")

        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "feature")
        )

        #expect(cacheAtom.worktreeFacts(for: worktreeId)?.pullRequestCount == 5)
        #expect(cacheAtom.worktreeFacts(for: worktreeId)?.enrichment?.branch == "feature")
    }

    @Test
    func worktreeEnrichmentReaderIgnoresPullRequestOnlyChanges() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let invalidationCounter = RepoCacheEntityMapInvalidationCounter()

        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )

        withObservationTracking {
            _ = cacheAtom.worktreeEnrichment(for: worktreeId)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.setPullRequestCount(2, for: worktreeId)

        #expect(!invalidationCounter.didFire)
        #expect(cacheAtom.worktreeEnrichment(for: worktreeId)?.branch == "main")
        #expect(cacheAtom.worktreeFacts(for: worktreeId)?.pullRequestCount == 2)
    }

    @Test
    func removeWorktreeClearsFactsAndSnapshots() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let invalidationCounter = RepoCacheEntityMapInvalidationCounter()

        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )
        cacheAtom.setPullRequestCount(4, for: worktreeId)

        withObservationTracking {
            _ = cacheAtom.worktreeFacts(for: worktreeId)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.removeWorktree(worktreeId)

        #expect(invalidationCounter.count == 1)
        #expect(cacheAtom.worktreeFacts(for: worktreeId) == nil)
        #expect(cacheAtom.worktreeEnrichmentSnapshot()[worktreeId] == nil)
        #expect(cacheAtom.pullRequestCountSnapshot()[worktreeId] == nil)
    }

    @Test
    func staleCacheCleanupPrunesMissingKeySlotsWithoutPruningValidMissingKeys() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let validRepoId = UUID()
        let staleRepoId = UUID()
        let validWorktreeId = UUID()
        let staleWorktreeId = UUID()

        #expect(cacheAtom.repoEnrichment(for: validRepoId) == nil)
        #expect(cacheAtom.repoEnrichment(for: staleRepoId) == nil)
        #expect(cacheAtom.worktreeFacts(for: validWorktreeId) == nil)
        #expect(cacheAtom.worktreeFacts(for: staleWorktreeId) == nil)
        #expect(cacheAtom.repoEnrichmentStorageSlotCount == 2)
        #expect(cacheAtom.worktreeEnrichmentStorageSlotCount == 2)
        #expect(cacheAtom.pullRequestCountStorageSlotCount == 2)

        let didPrune = cacheAtom.pruneNilSlots(
            validRepoIds: [validRepoId],
            validWorktreeIds: [validWorktreeId]
        )

        #expect(didPrune)
        #expect(cacheAtom.repoEnrichmentStorageSlotCount == 1)
        #expect(cacheAtom.worktreeEnrichmentStorageSlotCount == 1)
        #expect(cacheAtom.pullRequestCountStorageSlotCount == 1)

        cacheAtom.setRepoEnrichment(Self.localRepoEnrichment(repoId: validRepoId, displayName: "agent-studio"))
        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: validWorktreeId, repoId: validRepoId, branch: "main")
        )
        cacheAtom.setPullRequestCount(1, for: validWorktreeId)

        #expect(cacheAtom.repoEnrichment(for: validRepoId)?.displayName == "agent-studio")
        #expect(cacheAtom.worktreeFacts(for: validWorktreeId)?.enrichment?.branch == "main")
        #expect(cacheAtom.worktreeFacts(for: validWorktreeId)?.pullRequestCount == 1)
    }

    @Test
    func snapshotMethodsPreserveLegacyDictionaryShape() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let repoEnrichment = Self.localRepoEnrichment(repoId: repoId, displayName: "agent-studio")
        let worktreeEnrichment = WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")

        cacheAtom.setRepoEnrichment(repoEnrichment)
        cacheAtom.setWorktreeEnrichment(worktreeEnrichment)
        cacheAtom.setPullRequestCount(8, for: worktreeId)

        #expect(cacheAtom.repoEnrichmentSnapshot()[repoId] == repoEnrichment)
        #expect(cacheAtom.worktreeEnrichmentSnapshot()[worktreeId] == worktreeEnrichment)
        #expect(cacheAtom.pullRequestCountSnapshot()[worktreeId] == 8)
    }

    @Test
    func timestampOnlyWorktreeUpdateSkipsKeyInvalidationAndAggregateRevision() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let initial = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let timestampOnlyUpdate = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let invalidationCounter = RepoCacheEntityMapInvalidationCounter()

        cacheAtom.setWorktreeEnrichment(initial)
        let revisionBeforeEqualWrite = cacheAtom.cacheRevision

        withObservationTracking {
            _ = cacheAtom.worktreeFacts(for: worktreeId)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.setWorktreeEnrichment(timestampOnlyUpdate)

        #expect(!invalidationCounter.didFire)
        #expect(cacheAtom.cacheRevision == revisionBeforeEqualWrite)
        #expect(cacheAtom.worktreeFacts(for: worktreeId)?.enrichment?.updatedAt == initial.updatedAt)
    }

    @Test
    func timestampOnlyRepoUpdateSkipsKeyInvalidationAndAggregateRevision() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let initial = Self.localRepoEnrichment(
            repoId: repoId,
            displayName: "agent-studio",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let timestampOnlyUpdate = Self.localRepoEnrichment(
            repoId: repoId,
            displayName: "agent-studio",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let invalidationCounter = RepoCacheEntityMapInvalidationCounter()

        cacheAtom.setRepoEnrichment(initial)
        let revisionBeforeEqualWrite = cacheAtom.cacheRevision

        withObservationTracking {
            _ = cacheAtom.repoEnrichment(for: repoId)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.setRepoEnrichment(timestampOnlyUpdate)

        #expect(!invalidationCounter.didFire)
        #expect(cacheAtom.cacheRevision == revisionBeforeEqualWrite)
        #expect(cacheAtom.repoEnrichment(for: repoId) == initial)
    }

    @Test
    func sourceMetadataBumpsAggregateRevision() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let invalidationCounter = RepoCacheEntityMapInvalidationCounter()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        withObservationTracking {
            _ = cacheAtom.cacheRevision
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.markRebuilt(sourceRevision: 42, at: timestamp)

        #expect(invalidationCounter.count == 1)
        #expect(cacheAtom.cacheRevision == 1)
        #expect(cacheAtom.sourceRevision == 42)
        #expect(cacheAtom.lastRebuiltAt == timestamp)
    }

    private static func localRepoEnrichment(
        repoId: UUID,
        displayName: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> RepoEnrichment {
        .resolvedLocal(
            repoId: repoId,
            identity: RepoIdentity(
                groupKey: "local:\(displayName)",
                remoteSlug: nil,
                organizationName: nil,
                displayName: displayName
            ),
            updatedAt: updatedAt
        )
    }
}
