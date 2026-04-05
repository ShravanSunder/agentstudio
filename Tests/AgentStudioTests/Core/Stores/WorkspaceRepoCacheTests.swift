import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceRepoCacheTests {

    @Test
    func setRepoAndWorktreeEnrichment_persistsInMemoryState() {
        let store = WorkspaceRepoCache()
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
        let store = WorkspaceRepoCache()
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
        let store = WorkspaceRepoCache()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        store.markRebuilt(sourceRevision: 42, at: timestamp)

        #expect(store.sourceRevision == 42)
        #expect(store.lastRebuiltAt == timestamp)
    }

    @Test
    func recordRecentTarget_movesExistingEntryToFront_andCapsAtFifteen() {
        let store = WorkspaceRepoCache()
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
        let store = WorkspaceRepoCache()
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
