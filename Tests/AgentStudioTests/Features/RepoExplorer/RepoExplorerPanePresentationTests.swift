import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("RepoExplorer pane presentation")
struct RepoExplorerPanePresentationTests {
    @Test("projection fingerprint includes projected pane destination placement")
    func projectionFingerprintIncludesProjectedPaneDestinationPlacement() {
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let groupId = "pane-repo:\(repoId.uuidString)"
        let firstDestination = makeDestination(
            paneId: paneId,
            repoId: repoId,
            worktreeId: worktreeId,
            tabId: tabId,
            tabIndex: 0
        )
        let secondDestination = makeDestination(
            paneId: paneId,
            repoId: repoId,
            worktreeId: worktreeId,
            tabId: tabId,
            tabIndex: 1
        )

        #expect(
            RepoExplorerView.projectionFingerprint(
                for: makeProjection(groupId: groupId, repoId: repoId, destination: firstDestination)
            )
                != RepoExplorerView.projectionFingerprint(
                    for: makeProjection(groupId: groupId, repoId: repoId, destination: secondDestination)
                )
        )
    }

    @Test("semantic repo headers exist only for repo and pane perspectives")
    func semanticRepoHeadersExcludeTabPerspective() {
        let repo = RepoPresentationItem(
            id: UUIDv7.generate(),
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: []
        )
        let group = RepoPresentationGroup(
            id: "repo:\(repo.id.uuidString)",
            repoTitle: repo.name,
            organizationName: nil,
            repos: [repo]
        )

        #expect(RepoExplorerView.semanticRepoForHeader(group, groupingMode: .repo)?.id == repo.id)
        #expect(RepoExplorerView.semanticRepoForHeader(group, groupingMode: .pane)?.id == repo.id)
        #expect(RepoExplorerView.semanticRepoForHeader(group, groupingMode: .tab) == nil)
    }

    private func makeDestination(
        paneId: UUID,
        repoId: UUID,
        worktreeId: UUID,
        tabId: UUID,
        tabIndex: Int
    ) -> RepoExplorerPaneDestination {
        RepoExplorerPaneDestination(
            paneId: paneId,
            repoId: repoId,
            worktreeId: worktreeId,
            worktreeLabel: "main",
            tabId: tabId,
            tabIndex: tabIndex,
            paneIndexInTab: 0,
            isActiveInTab: true
        )
    }

    private func makeProjection(
        groupId: String,
        repoId: UUID,
        destination: RepoExplorerPaneDestination
    ) -> RepoExplorerSidebarProjection {
        let worktree = Worktree(
            id: destination.worktreeId,
            repoId: repoId,
            name: destination.worktreeLabel,
            path: URL(fileURLWithPath: "/tmp/\(destination.worktreeLabel)")
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "repo",
            repoPath: worktree.path,
            stableKey: "repo",
            worktrees: [worktree]
        )
        let group = RepoPresentationGroup(
            id: groupId,
            repoTitle: repo.name,
            organizationName: nil,
            repos: [repo]
        )
        return .ready(
            RepoExplorerSidebarContent(
                sections: [
                    RepoExplorerSidebarSection(
                        kind: .repositories,
                        resolvedGroups: [group],
                        loadingRepos: []
                    )
                ],
                resolvedGroups: [group],
                paneRowsByGroupId: [
                    groupId: [
                        RepoExplorerProjectedPaneRow(
                            groupId: groupId,
                            repoId: repoId,
                            destination: destination,
                            rowId: "pane-row"
                        )
                    ]
                ],
                loadingRepos: [],
                emptyState: .content
            )
        )
    }
}
