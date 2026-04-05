import Foundation
import Testing

@testable import AgentStudio

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
    func removeRepo_prunesWorktreeAndCounters() {
        let store = RepoCacheAtom()
        let repoId = UUID()
        let worktreeId = UUID()

        store.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        store.setWorktreeEnrichment(.init(worktreeId: worktreeId, repoId: repoId, branch: "feature"))
        store.setPullRequestCount(2, for: worktreeId)
        store.setNotificationCount(5, for: worktreeId)

        store.removeRepo(repoId)

        #expect(store.repoEnrichmentByRepoId[repoId] == nil)
        #expect(store.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(store.pullRequestCountByWorktreeId[worktreeId] == nil)
        #expect(store.notificationCountByWorktreeId[worktreeId] == nil)
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
    func recordRecentTarget_movesExistingEntryToFront_andCapsAtSix() {
        let store = RepoCacheAtom()
        let targets = (0..<6).map { index in
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

        #expect(store.recentTargets.count == 6)
        #expect(store.recentTargets.first?.id == targets[2].id)
        #expect(store.recentTargets.contains { $0.id == targets[0].id })
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
}
