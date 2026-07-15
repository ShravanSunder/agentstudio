import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Repo Explorer duplicate topology containment")
struct RepoExplorerDuplicateTopologyContainmentTests {
    @Test("duplicate worktree identities do not produce duplicate sidebar row identities")
    func duplicateWorktreeIdentitiesDoNotProduceDuplicateSidebarRowIdentities() {
        let duplicatedWorktreeId = UUID()
        let repoId = UUID()
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [
                Worktree(
                    id: duplicatedWorktreeId,
                    repoId: repoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/agent-studio")
                ),
                Worktree(
                    id: duplicatedWorktreeId,
                    repoId: repoId,
                    name: "renamed",
                    path: URL(fileURLWithPath: "/tmp/agent-studio-renamed")
                ),
            ]
        )
        let group = RepoPresentationGroup(
            id: "remote:askluna/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "askluna",
            repos: [repo]
        )

        let rowIndex = RepoExplorerRowIndex(
            projection: RepoExplorerSidebarProjection(
                resolvedGroups: [group],
                loadingRepos: [],
                showsNoResults: false
            ),
            expandedGroupIds: [group.id],
            isFiltering: false
        )

        guard case .degraded(.duplicateWorktreeIdentities(let duplicateIdentities)) = rowIndex.state else {
            Issue.record("Expected duplicate worktree identity fault")
            return
        }
        let duplicateIdentity = duplicateIdentities.first

        guard case .topologyFault(let entryFault) = rowIndex.entries.first else {
            Issue.record("Expected the degraded row index to expose a fault row")
            return
        }

        #expect(rowIndex.entries.count == 1)
        #expect(Set(rowIndex.entries.map(\.id)).count == rowIndex.entries.count)
        #expect(entryFault == .duplicateWorktreeIdentities(duplicateIdentities))
        #expect(rowIndex.worktreeIds.isEmpty)
        #expect(duplicateIdentity?.worktreeId == duplicatedWorktreeId)
        #expect(
            duplicateIdentity?.claims.map(\.path.path) == [
                "/tmp/agent-studio", "/tmp/agent-studio-renamed",
            ])
        #expect(
            rowIndex.resolve(
                groupId: group.id,
                repoId: repoId,
                worktreeId: duplicatedWorktreeId
            ) == nil
        )
    }
}
