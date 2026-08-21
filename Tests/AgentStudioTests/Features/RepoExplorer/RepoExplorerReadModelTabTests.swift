import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    @Test("By Tab keeps one stored-order tab section regardless of favorites")
    func tabGroupsKeepStoredOrderWithoutFavoritePartitions() {
        let favoriteRepoId = UUIDv7.generate()
        let regularRepoId = UUIDv7.generate()
        let favoriteWorktree = worktree(repoId: favoriteRepoId, name: "favorite")
        let regularWorktree = worktree(repoId: regularRepoId, name: "regular")
        let earlierTabId = UUIDv7.generate()
        let laterTabId = UUIDv7.generate()
        let repositories = [
            repo(id: favoriteRepoId, name: "favorite", isFavorite: true, worktrees: [favoriteWorktree]),
            repo(id: regularRepoId, name: "regular", worktrees: [regularWorktree]),
        ]
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: [
                    favoriteRepoId: resolvedRemote(repoId: favoriteRepoId),
                    regularRepoId: resolvedRemote(repoId: regularRepoId),
                ],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    favoriteWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
                            tabId: laterTabId,
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        )
                    ],
                    regularWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
                            tabId: earlierTabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                ]
            )
        )

        #expect(projection.sections.map(\.kind) == [.tabs])
        #expect(
            projection.resolvedGroups.map(\.id) == [
                "tab:\(earlierTabId.uuidString)",
                "tab:\(laterTabId.uuidString)",
            ]
        )
        #expect(projection.resolvedGroups.flatMap(\.repos).map(\.id) == [regularRepoId, favoriteRepoId])
    }

    @Test("By Tab disclosure state collapses the complete tab")
    func tabDisclosureStateCollapsesCompleteTab() {
        let repoId = UUIDv7.generate()
        let worktree = worktree(repoId: repoId)
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "repository", worktrees: [worktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ]
            )
        )

        let expanded = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        let collapsed = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: ["tab:\(tabId.uuidString)"],
            isFiltering: false
        )

        #expect(expanded.entries.contains { if case .resolvedPaneRow = $0 { true } else { false } })
        #expect(!collapsed.entries.contains { if case .resolvedPaneRow = $0 { true } else { false } })
    }
}
