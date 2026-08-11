import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class RepoCacheAtomFamilyInvalidationCounter: @unchecked Sendable {
    var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
private func observePullRequestFacts(
    in cacheAtom: RepoEnrichmentCacheAtom,
    key: RepoBranchKey,
    counter: RepoCacheAtomFamilyInvalidationCounter
) {
    withObservationTracking {
        _ = cacheAtom.pullRequestFacts(for: key)
    } onChange: {
        MainActor.assumeIsolated {
            counter.record()
            observePullRequestFacts(in: cacheAtom, key: key, counter: counter)
        }
    }
}

@MainActor
@Suite(.serialized)
struct RepoCacheAtomFamilyTests {
    @Test
    func repoBranchKeyRejectsOnlyEmptyBranchAndPreservesExactBranchText() {
        let repoId = UUID()

        #expect(RepoBranchKey(repoId: repoId, branch: "") == nil)
        #expect(RepoBranchKey(repoId: repoId, branch: " feature/exact ")?.branch == " feature/exact ")
    }

    @Test
    func repoEnrichmentKeyReadInvalidatesOnlyMatchingRepo() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let watchedRepoId = UUID()
        let unrelatedRepoId = UUID()
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()

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
    func pullRequestFactsKeyReadInvalidatesOnlyMatchingRepositoryBranch() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let watchedKey = RepoBranchKey(repoId: repoId, branch: "main")!
        let unrelatedKey = RepoBranchKey(repoId: repoId, branch: "feature/unrelated")!
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()

        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: [
                "main": PullRequestFacts(
                    openCount: 1, exactOpenURL: URL(string: "https://github.com/acme/repo/pull/1")),
                "feature/unrelated": PullRequestFacts(openCount: 2, exactOpenURL: nil),
            ]
        )

        withObservationTracking {
            _ = cacheAtom.pullRequestFacts(for: watchedKey)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: ["feature/unrelated": PullRequestFacts(openCount: 3, exactOpenURL: nil)]
        )

        #expect(!invalidationCounter.didFire)
        #expect(cacheAtom.pullRequestFacts(for: watchedKey)?.openCount == 1)
        #expect(cacheAtom.pullRequestFacts(for: unrelatedKey)?.openCount == 3)
    }

    @Test
    func applyPullRequestFactsMergesOnlyRefreshedBranches() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let branchAKey = RepoBranchKey(repoId: repoId, branch: "feature/a")!
        let branchBKey = RepoBranchKey(repoId: repoId, branch: "feature/b")!

        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: [
                "feature/a": PullRequestFacts(openCount: 1, exactOpenURL: nil),
                "feature/b": PullRequestFacts(openCount: 2, exactOpenURL: nil),
            ]
        )
        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: ["feature/a": PullRequestFacts(openCount: 4, exactOpenURL: nil)]
        )

        #expect(cacheAtom.pullRequestFacts(for: branchAKey)?.openCount == 4)
        #expect(cacheAtom.pullRequestFacts(for: branchBKey)?.openCount == 2)
    }

    @Test
    func pullRequestFactsRetainObservationIdentityAcrossRemovalAndReinsertion() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let key = RepoBranchKey(repoId: repoId, branch: "main")!
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()
        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: ["main": PullRequestFacts(openCount: 1, exactOpenURL: nil)]
        )
        observePullRequestFacts(
            in: cacheAtom,
            key: key,
            counter: invalidationCounter
        )

        cacheAtom.removePullRequestFacts(repoId: repoId, branches: ["main"])
        #expect(invalidationCounter.count == 1)
        #expect(cacheAtom.pullRequestFacts(for: key) == nil)

        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: ["main": PullRequestFacts(openCount: 2, exactOpenURL: nil)]
        )
        #expect(invalidationCounter.count == 2)
        #expect(cacheAtom.pullRequestFacts(for: key)?.openCount == 2)
    }

    @Test
    func missingKeySlotsRemainRetainedForTheCacheOwnerLifetime() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let validRepoId = UUID()
        let staleRepoId = UUID()
        let validBranchKey = RepoBranchKey(repoId: validRepoId, branch: "main")!
        let staleBranchKey = RepoBranchKey(repoId: staleRepoId, branch: "main")!

        #expect(cacheAtom.repoEnrichment(for: validRepoId) == nil)
        #expect(cacheAtom.repoEnrichment(for: staleRepoId) == nil)
        #expect(cacheAtom.pullRequestFacts(for: validBranchKey) == nil)
        #expect(cacheAtom.pullRequestFacts(for: staleBranchKey) == nil)
        #expect(cacheAtom.repoEnrichmentStorageSlotCount == 2)
        #expect(cacheAtom.pullRequestFactsStorageSlotCount == 2)

        #expect(cacheAtom.repoEnrichmentStorageSlotCount == 2)
        #expect(cacheAtom.pullRequestFactsStorageSlotCount == 2)

        cacheAtom.setRepoEnrichment(Self.localRepoEnrichment(repoId: validRepoId, displayName: "agent-studio"))
        cacheAtom.applyPullRequestFacts(
            repoId: validRepoId,
            factsByBranch: ["main": PullRequestFacts(openCount: 1, exactOpenURL: nil)]
        )

        #expect(cacheAtom.repoEnrichment(for: validRepoId)?.displayName == "agent-studio")
        #expect(cacheAtom.pullRequestFacts(for: validBranchKey)?.openCount == 1)
    }

    @Test
    func pullRequestFactsSnapshotUsesRepositoryBranchKeys() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let key = RepoBranchKey(repoId: repoId, branch: "main")!
        let repoEnrichment = Self.localRepoEnrichment(repoId: repoId, displayName: "agent-studio")

        cacheAtom.setRepoEnrichment(repoEnrichment)
        cacheAtom.applyPullRequestFacts(
            repoId: repoId,
            factsByBranch: ["main": PullRequestFacts(openCount: 8, exactOpenURL: nil)]
        )

        #expect(cacheAtom.repoEnrichmentSnapshot()[repoId] == repoEnrichment)
        #expect(cacheAtom.pullRequestFactsSnapshot()[key]?.openCount == 8)
    }

    @Test
    func contentEqualPullRequestFactsWriteSkipsKeyInvalidationAndAggregateRevision() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let key = RepoBranchKey(repoId: repoId, branch: "main")!
        let facts = PullRequestFacts(
            openCount: 1,
            exactOpenURL: URL(string: "https://github.com/acme/repo/pull/1")
        )
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()

        cacheAtom.applyPullRequestFacts(repoId: repoId, factsByBranch: ["main": facts])
        let revisionBeforeEqualWrite = cacheAtom.cacheRevision
        withObservationTracking {
            _ = cacheAtom.pullRequestFacts(for: key)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.applyPullRequestFacts(repoId: repoId, factsByBranch: ["main": facts])

        #expect(!invalidationCounter.didFire)
        #expect(cacheAtom.cacheRevision == revisionBeforeEqualWrite)
    }

    @Test
    func repositoryInvalidationRemovesOnlyMatchingRepositoryFacts() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let removedRepoId = UUID()
        let retainedRepoId = UUID()
        let removedKey = RepoBranchKey(repoId: removedRepoId, branch: "main")!
        let retainedKey = RepoBranchKey(repoId: retainedRepoId, branch: "main")!
        cacheAtom.applyPullRequestFacts(
            repoId: removedRepoId,
            factsByBranch: ["main": PullRequestFacts(openCount: 1, exactOpenURL: nil)]
        )
        cacheAtom.applyPullRequestFacts(
            repoId: retainedRepoId,
            factsByBranch: ["main": PullRequestFacts(openCount: 2, exactOpenURL: nil)]
        )

        cacheAtom.removePullRequestFacts(forRepository: removedRepoId)

        #expect(cacheAtom.pullRequestFacts(for: removedKey) == nil)
        #expect(cacheAtom.pullRequestFacts(for: retainedKey)?.openCount == 2)
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
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()

        cacheAtom.setWorktreeEnrichment(initial)
        let revisionBeforeEqualWrite = cacheAtom.cacheRevision

        withObservationTracking {
            _ = cacheAtom.worktreeEnrichment(for: worktreeId)
        } onChange: {
            invalidationCounter.record()
        }

        cacheAtom.setWorktreeEnrichment(timestampOnlyUpdate)

        #expect(!invalidationCounter.didFire)
        #expect(cacheAtom.cacheRevision == revisionBeforeEqualWrite)
        #expect(cacheAtom.worktreeEnrichment(for: worktreeId)?.updatedAt == initial.updatedAt)
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
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()

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
        let invalidationCounter = RepoCacheAtomFamilyInvalidationCounter()
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
