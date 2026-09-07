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
            .activitySubgroup(groupID: groupID, bucket: .active),
            .activitySubgroup(groupID: groupID, bucket: .justNow),
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

    @Test("activity subgroup identity includes both parent group and bucket")
    func activitySubgroupIdentityIncludesParentGroupAndBucket() {
        let first = RepoExplorerListEntry.activitySubgroup(groupId: "first", bucket: .active)
        let differentGroup = RepoExplorerListEntry.activitySubgroup(groupId: "second", bucket: .active)
        let differentBucket = RepoExplorerListEntry.activitySubgroup(groupId: "first", bucket: .justNow)

        #expect(first.id == .activitySubgroup(groupID: "first", bucket: .active))
        #expect(Set([first.id, differentGroup.id, differentBucket.id]).count == 3)
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
