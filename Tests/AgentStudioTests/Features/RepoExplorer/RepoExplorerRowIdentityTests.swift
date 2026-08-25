import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerRowIdentityTests")
struct RepoExplorerRowIdentityTests {
    @Test("closed typed identities distinguish every row variant without rendered strings")
    func closedTypedIdentitiesDistinguishEveryRowVariant() {
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let groupID = "remote:askluna/agent-studio"
        let identities: [RepoExplorerRowID] = [
            .sectionHeader(.repositories),
            .loadingSectionHeader(.repositories),
            .loadingRepository(section: .repositories, repoID: repoID),
            .group(groupID: groupID),
            .worktree(groupID: groupID, repoID: repoID, worktreeID: worktreeID),
            .associatedPane(
                groupID: groupID,
                repoID: repoID,
                worktreeID: worktreeID,
                paneID: paneID
            ),
            .tabPane(groupID: "tab-group", paneID: paneID),
            .unassociatedPane(paneID: paneID),
            .topologyFault,
        ]

        #expect(Set(identities).count == identities.count)
        #expect(identities == identities.map { $0 })
    }

    @Test("list entries expose the worker-provided typed row identity")
    func listEntriesExposeTypedIdentity() {
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let rowID = RepoExplorerRowID.worktree(
            groupID: "repo-group",
            repoID: repoID,
            worktreeID: worktreeID
        )
        let entry = RepoExplorerListEntry.resolvedWorktreeRow(
            groupId: "repo-group",
            repoId: repoID,
            worktreeId: worktreeID,
            rowId: rowID
        )

        #expect(entry.id == rowID)
    }
}
