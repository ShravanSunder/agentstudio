import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceCacheStoreTests {

    @Test
    func setRepoAndWorktreeEnrichment_persistsInMemoryState() {
        let store = WorkspaceCacheStore()
        let repoId = UUID()
        let worktreeId = UUID()

        let repoEnrichment = RepoEnrichment.resolved(
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
        let store = WorkspaceCacheStore()
        let repoId = UUID()
        let worktreeId = UUID()

        store.setRepoEnrichment(.unresolved(repoId: repoId))
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
        let store = WorkspaceCacheStore()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        store.markRebuilt(sourceRevision: 42, at: timestamp)

        #expect(store.sourceRevision == 42)
        #expect(store.lastRebuiltAt == timestamp)
    }
}
