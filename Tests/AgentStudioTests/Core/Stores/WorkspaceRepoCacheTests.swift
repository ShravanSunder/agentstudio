import Foundation
import Observation
import Testing

@testable import AgentStudio

private final class RepoCacheObservationInvalidationCounter: @unchecked Sendable {
    var didInvalidate = false
}

@Suite(.serialized)
@MainActor
final class RepoCacheAtomTests {

    @Test
    func setRepoAndWorktreeEnrichment_persistsInMemoryState() {
        let store = RepoCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()

        let repoEnrichment = RepoEnrichment.resolvedRemote(
            repoId: repoId,
            raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:askluna/agent-studio",
                remoteSlug: "askluna/agent-studio",
                organizationName: "askluna",
                displayName: "agent-studio"
            ),
            updatedAt: Date()
        )
        let worktreeEnrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main"
        )

        store.setRepoEnrichment(repoEnrichment)
        store.setWorktreeEnrichment(worktreeEnrichment)

        #expect(store.repoEnrichmentByRepoId[repoId]?.organizationName == "askluna")
        #expect(store.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
    }

    @Test
    func setWorktreeEnrichment_skipsTimestampOnlyCacheContentRewrite() {
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
        let invalidationCounter = RepoCacheObservationInvalidationCounter()

        cacheAtom.setWorktreeEnrichment(initial)
        withObservationTracking {
            _ = cacheAtom.worktreeEnrichmentByWorktreeId
        } onChange: {
            invalidationCounter.didInvalidate = true
        }

        cacheAtom.setWorktreeEnrichment(timestampOnlyUpdate)

        #expect(!invalidationCounter.didInvalidate)
        #expect(cacheAtom.worktreeEnrichmentByWorktreeId[worktreeId]?.updatedAt == initial.updatedAt)
    }

    @Test
    func setWorktreeEnrichment_rewritesWhenSnapshotContentChanges() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let initialSnapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: rootPath,
            summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
            branch: "main"
        )
        let nextSnapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: rootPath,
            summary: GitWorkingTreeSummary(changed: 2, staged: 0, untracked: 0),
            branch: "main"
        )
        let invalidationCounter = RepoCacheObservationInvalidationCounter()

        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "main",
                snapshot: initialSnapshot,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        withObservationTracking {
            _ = cacheAtom.worktreeEnrichmentByWorktreeId
        } onChange: {
            invalidationCounter.didInvalidate = true
        }

        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "main",
                snapshot: nextSnapshot,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(invalidationCounter.didInvalidate)
        #expect(cacheAtom.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot == nextSnapshot)
    }

    @Test
    func removeRepo_prunesWorktreeAndPullRequestCounters() {
        let store = RepoCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()

        store.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        store.setWorktreeEnrichment(.init(worktreeId: worktreeId, repoId: repoId, branch: "feature"))
        store.setPullRequestCount(2, for: worktreeId)

        store.removeRepo(repoId)

        #expect(store.repoEnrichmentByRepoId[repoId] == nil)
        #expect(store.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(store.pullRequestCountByWorktreeId[worktreeId] == nil)
    }

    @Test
    func markRebuilt_updatesRevisionAndTimestamp() {
        let store = RepoCacheAtom()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        store.markRebuilt(sourceRevision: 42, at: timestamp)

        #expect(store.sourceRevision == 42)
        #expect(store.lastRebuiltAt == timestamp)
    }

    @Test
    func recordRecentTarget_movesExistingEntryToFront_andCapsAtFifteen() {
        let store = RepoCacheAtom()
        let targets = (0..<16).map { index in
            RecentWorkspaceTarget.forCwd(
                URL(fileURLWithPath: "/tmp/project-\(index)"),
                title: "project-\(index)",
                lastOpenedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        for target in targets {
            store.recordRecentTarget(target)
        }
        store.recordRecentTarget(targets[2])

        #expect(store.recentTargets.count == 15)
        #expect(store.recentTargets.first?.id == targets[2].id)
        #expect(store.recentTargets.contains { $0.id == targets[0].id } == false)
    }

    @Test
    func removeRecentTarget_removesMatchingId_andMissingIdIsNoOp() {
        let store = RepoCacheAtom()
        let first = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/first"))
        let second = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/second"))

        store.recordRecentTarget(first)
        store.recordRecentTarget(second)

        store.removeRecentTarget(first.id)

        #expect(store.recentTargets == [second])

        store.removeRecentTarget("cwd:/tmp/missing")

        #expect(store.recentTargets == [second])
    }

    @Test
    func composedRepoCacheRoutesMutationsToSplitOwners() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheAtom(
            enrichmentCacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom
        )
        let repoId = UUID()
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))

        store.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        store.recordRecentTarget(target)

        #expect(cacheAtom.repoEnrichmentByRepoId[repoId] == .awaitingOrigin(repoId: repoId))
        #expect(recentTargetAtom.recentTargets == [target])
    }

    @Test
    func clearingEnrichmentCacheDoesNotClearRecentTargets() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheAtom(
            enrichmentCacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom
        )
        let repoId = UUID()
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))

        store.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        store.recordRecentTarget(target)

        cacheAtom.clear()

        #expect(store.repoEnrichmentByRepoId.isEmpty)
        #expect(store.recentTargets == [target])
    }

    @Test
    func composedRepoCacheObservationTracksEnrichmentOwner() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheAtom(
            enrichmentCacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom
        )
        let repoId = UUID()
        let invalidationCounter = RepoCacheObservationInvalidationCounter()

        withObservationTracking {
            _ = store.repoEnrichmentByRepoId
            _ = store.recentTargets
        } onChange: {
            invalidationCounter.didInvalidate = true
        }

        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: repoId))

        #expect(invalidationCounter.didInvalidate)
    }

    @Test
    func composedRepoCacheObservationTracksRecentTargetOwner() {
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheAtom(
            enrichmentCacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom
        )
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))
        let invalidationCounter = RepoCacheObservationInvalidationCounter()

        withObservationTracking {
            _ = store.recentTargets
        } onChange: {
            invalidationCounter.didInvalidate = true
        }

        recentTargetAtom.recordRecentTarget(target)

        #expect(invalidationCounter.didInvalidate)
    }
}
