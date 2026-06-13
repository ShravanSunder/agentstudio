import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoExplorer read models")
struct RepoExplorerReadModelTests {
    @Test("projection separates resolved and loading repos while preserving filter semantics")
    func projectionSeparatesResolvedAndLoadingRepos() {
        let resolvedRepoId = UUID()
        let loadingRepoId = UUID()
        let resolvedRepo = repo(
            id: resolvedRepoId,
            name: "agent-studio",
            worktrees: [
                worktree(repoId: resolvedRepoId, name: "main"),
                worktree(repoId: resolvedRepoId, name: "perf-sidebar"),
            ]
        )
        let loadingRepo = repo(id: loadingRepoId, name: "agent-vm", worktrees: [worktree(repoId: loadingRepoId)])

        let snapshot = RepoExplorerSnapshot(
            repos: [resolvedRepo, loadingRepo],
            repoEnrichmentByRepoId: [
                resolvedRepoId: .resolvedLocal(
                    repoId: resolvedRepoId,
                    identity: RepoIdentity(
                        groupKey: "path:/tmp/agent-studio",
                        remoteSlug: nil,
                        organizationName: nil,
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date(timeIntervalSince1970: 0)
                ),
                loadingRepoId: .awaitingOrigin(repoId: loadingRepoId),
            ],
            query: "perf"
        )

        let projection = RepoExplorerProjection.project(snapshot)

        #expect(projection.resolvedGroups.count == 1)
        #expect(projection.resolvedGroups[0].repos[0].worktrees.map(\.name) == ["perf-sidebar"])
        #expect(projection.loadingRepos.isEmpty)
        #expect(projection.showsNoResults == false)
    }

    @Test("row index resolves worktree rows without walking the rendered groups")
    func rowIndexResolvesWorktreeRows() {
        let repoId = UUID()
        let main = worktree(repoId: repoId, name: "main", isMain: true)
        let feature = worktree(repoId: repoId, name: "feature")
        let repo = repo(id: repoId, name: "agent-studio", worktrees: [feature, main])
        let group = RepoPresentationGroup(
            id: "path:/tmp/agent-studio",
            repoTitle: "agent-studio",
            organizationName: nil,
            repos: [repo]
        )
        let projection = RepoExplorerSidebarProjection(
            resolvedGroups: [group],
            loadingRepos: [],
            showsNoResults: false
        )

        let index = RepoExplorerRowIndex(
            projection: projection,
            expandedGroupIds: [group.id],
            isFiltering: false
        )

        #expect(index.entries.count == 3)
        guard case .resolvedWorktreeRow(let groupId, let indexedRepoId, let worktreeId) = index.entries[1] else {
            Issue.record("Expected main worktree row after group header")
            return
        }

        let context = index.resolve(groupId: groupId, repoId: indexedRepoId, worktreeId: worktreeId)
        #expect(context?.group.id == group.id)
        #expect(context?.repo.id == repo.id)
        #expect(context?.worktree.id == main.id)
    }

    private func repo(id: UUID, name: String, worktrees: [Worktree]) -> RepoPresentationItem {
        RepoPresentationItem(
            id: id,
            name: name,
            repoPath: URL(fileURLWithPath: "/tmp/\(name)"),
            stableKey: name,
            worktrees: worktrees
        )
    }

    private func worktree(repoId: UUID, name: String = "main", isMain: Bool = false) -> Worktree {
        Worktree(
            repoId: repoId,
            name: name,
            path: URL(fileURLWithPath: "/tmp/\(name)"),
            isMainWorktree: isMain
        )
    }
}
