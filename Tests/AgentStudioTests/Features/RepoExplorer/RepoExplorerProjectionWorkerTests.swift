import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoExplorerProjectionWorker")
struct RepoExplorerProjectionWorkerTests {
    @Test("worker projects sidebar model and row index off caller isolation")
    func workerProjectsSidebarModelAndRowIndex() async throws {
        let repoId = UUID()
        let matchingWorktree = Worktree(
            repoId: repoId,
            name: "feature",
            path: URL(fileURLWithPath: "/tmp/feature"),
            isMainWorktree: false
        )
        let filteredWorktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/main"),
            isMainWorktree: true
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [filteredWorktree, matchingWorktree]
        )
        let snapshot = RepoExplorerSnapshot(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repoId: .resolvedRemote(
                    repoId: repoId,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:askluna/agent-studio",
                        remoteSlug: "askluna/agent-studio",
                        organizationName: "askluna",
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            ],
            groupingMode: .repo,
            sortOrder: .ascending,
            query: "feature"
        )
        let request = RepoExplorerProjectionRequest(
            generation: 3,
            snapshot: snapshot,
            expandedGroupIds: [],
            isFiltering: true,
            trigger: "search"
        )

        let result = try await RepoExplorerProjectionWorker().project(request)

        #expect(result.generation == 3)
        #expect(result.snapshot == snapshot)
        #expect(result.trigger == "search")
        #expect(result.rowIndex.entries.count == 2)
        let visibleWorktreeIds = result.projection.resolvedGroups.first?.repos.first?.worktrees.map { $0.id }
        #expect(visibleWorktreeIds == [matchingWorktree.id])
        #expect(result.workerDuration > .zero)
    }
}
