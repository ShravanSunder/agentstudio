import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorer read models")
struct RepoExplorerReadModelTests {}

extension RepoExplorerReadModelTests {
    @Test("status-unavailable repo is no longer projected as scanning")
    func statusUnavailableRepoIsNotProjectedAsScanning() {
        let repoId = UUIDv7.generate()
        let unavailableRepo = repo(id: repoId, name: "slow-repo", worktrees: [worktree(repoId: repoId)])
        let enrichmentByRepoId: [UUID: RepoEnrichment] = [
            repoId: .statusUnavailable(repoId: repoId, reason: "timeout")
        ]

        #expect(RepoExplorerProjection.loadingRepos([unavailableRepo], enrichmentByRepoId: enrichmentByRepoId).isEmpty)
        #expect(
            RepoExplorerProjection.statusUnavailableRepos(
                [unavailableRepo],
                enrichmentByRepoId: enrichmentByRepoId
            ).map(\.id) == [repoId]
        )
    }

    @Test("status-unavailable section state does not leak into scanning-only sections")
    func statusUnavailableSectionStateIsSectionLocal() {
        let unavailableRepoId = UUIDv7.generate()
        let scanningRepoId = UUIDv7.generate()
        let unavailableRepo = repo(
            id: unavailableRepoId,
            name: "favorite-unavailable",
            isPinned: true,
            worktrees: [worktree(repoId: unavailableRepoId)]
        )
        let scanningRepo = repo(
            id: scanningRepoId,
            name: "scanning",
            worktrees: [worktree(repoId: scanningRepoId)]
        )
        let enrichmentByRepoId: [UUID: RepoEnrichment] = [
            unavailableRepoId: .statusUnavailable(repoId: unavailableRepoId, reason: "timeout"),
            scanningRepoId: .awaitingOrigin(repoId: scanningRepoId),
        ]

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [unavailableRepo, scanningRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                query: ""
            )
        )

        #expect(projection.sections[0].loadingState(enrichmentByRepoId: enrichmentByRepoId) == .statusUnavailable)
        #expect(projection.sections[1].loadingState(enrichmentByRepoId: enrichmentByRepoId) == .scanning)
        #expect(projection.scanningRepoCount(enrichmentByRepoId: enrichmentByRepoId) == 1)
    }

    @Test("same section reports scanning and unavailable repos without conflation")
    func sameSectionReportsMixedLoadingState() {
        let unavailableRepoId = UUIDv7.generate()
        let scanningRepoId = UUIDv7.generate()
        let enrichmentByRepoId: [UUID: RepoEnrichment] = [
            unavailableRepoId: .statusUnavailable(repoId: unavailableRepoId, reason: "timeout"),
            scanningRepoId: .awaitingOrigin(repoId: scanningRepoId),
        ]
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [
                    repo(id: unavailableRepoId, name: "unavailable", worktrees: [worktree(repoId: unavailableRepoId)]),
                    repo(id: scanningRepoId, name: "scanning", worktrees: [worktree(repoId: scanningRepoId)]),
                ],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                query: ""
            )
        )

        #expect(projection.sections[0].loadingState(enrichmentByRepoId: enrichmentByRepoId) == .mixed)
    }

    @Test("grouping modes are exactly repo pane and tab")
    func groupingModesAreExactlyRepoPaneAndTab() {
        #expect(RepoExplorerGroupingMode.allCases == [.repo, .tab, .activity])
        #expect(RepoExplorerGroupingMode.allCases.map(\.title) == ["Repo", "Tab", "Activity"])
        #expect(
            RepoExplorerGroupingMode.allCases.map(\.icon) == [
                .system(.folder),
                .system(.rectangleStack),
                .system(.clock),
            ])
    }

    @Test("sort order defaults ascending while repository group order stays stable")
    func sortOrderDefaultsAscendingAndRepositoryGroupOrderStaysStable() {
        #expect(RepoExplorerSortOrder.default == .ascending)
        #expect(RepoExplorerSortOrder.ascending.toggled == .descending)
        #expect(RepoExplorerSortOrder.descending.toggled == .ascending)

        let firstRepoId = UUID()
        let secondRepoId = UUID()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [
                    repo(id: firstRepoId, name: "actual-server", worktrees: [worktree(repoId: firstRepoId)]),
                    repo(id: secondRepoId, name: "agent-browser", worktrees: [worktree(repoId: secondRepoId)]),
                ],
                repoEnrichmentByRepoId: [
                    firstRepoId: resolvedRemote(repoId: firstRepoId, displayName: "actual-server"),
                    secondRepoId: resolvedRemote(repoId: secondRepoId, displayName: "agent-browser"),
                ],
                groupingMode: .repo,
                sortOrder: .descending,
                query: ""
            )
        )

        #expect(projection.resolvedGroups.map(\.repoTitle) == ["actual-server", "agent-browser"])
    }

    @Test("repository pins partition Repos without influencing Panes grouping")
    func repositoryPinsPartitionReposWithoutInfluencingPanesGrouping() {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalWorktree = worktree(repoId: normalRepoId, name: "z-normal")
        let favoriteWorktree = worktree(repoId: favoriteRepoId, name: "a-favorite")
        let normalRepo = repo(id: normalRepoId, name: "alpha-normal", worktrees: [normalWorktree])
        let favoriteRepo = repo(
            id: favoriteRepoId,
            name: "zeta-favorite",
            isPinned: true,
            worktrees: [favoriteWorktree]
        )
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let tabId = UUID()

        let enrichmentByRepoId = [
            normalRepoId: resolvedRemote(repoId: normalRepoId, displayName: "alpha-normal"),
            favoriteRepoId: resolvedRemote(repoId: favoriteRepoId, displayName: "zeta-favorite"),
        ]
        let locationsByWorktreeId = [
            normalWorktree.id: [
                WorkspacePaneLocation(
                    paneId: firstPaneId,
                    tabId: tabId,
                    tabIndex: 0,
                    paneIndexInTab: 0,
                    isActiveInTab: true
                )
            ],
            favoriteWorktree.id: [
                WorkspacePaneLocation(
                    paneId: secondPaneId,
                    tabId: tabId,
                    tabIndex: 0,
                    paneIndexInTab: 1,
                    isActiveInTab: false
                )
            ],
        ]

        let repoProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .repo,
                sortOrder: .ascending,
                query: ""
            )
        )
        let paneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                surface: .panes,
                groupingMode: .repo,
                sortOrder: .ascending,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )
        let tabProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                surface: .panes,
                groupingMode: .tab,
                sortOrder: .ascending,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )

        #expect(repoProjection.resolvedGroups.map(\.repoTitle) == ["zeta-favorite", "alpha-normal"])
        #expect(repoProjection.sections.map(\.kind) == [.pinnedRepositories, .repositories])
        #expect(repoProjection.sections.map(\.title) == ["Pinned repos", "Available repos"])
        #expect(repoProjection.sections[0].resolvedGroups.map(\.repoTitle) == ["zeta-favorite"])
        #expect(repoProjection.sections[1].resolvedGroups.map(\.repoTitle) == ["alpha-normal"])
        #expect(
            paneProjection.resolvedGroups.map(\.id) == [
                "panes:panes:repo:\(normalRepoId.uuidString)",
                "panes:panes:repo:\(favoriteRepoId.uuidString)",
            ]
        )
        #expect(paneProjection.resolvedGroups.first?.repos.map(\.id) == [normalRepoId])
        #expect(paneProjection.resolvedGroups.last?.repos.map(\.id) == [favoriteRepoId])
        #expect(paneProjection.sections.map(\.kind) == [.panes])
        #expect(tabProjection.resolvedGroups.count == 1)
        #expect(tabProjection.resolvedGroups[0].repos.map(\.id) == [normalRepoId, favoriteRepoId])
        #expect(tabProjection.sections.map(\.kind) == [.panes])
    }

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

    @Test("favorites-first projection retains all resolved repos")
    func favoritesFirstProjectionRetainsAllResolvedRepos() {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalRepo = repo(id: normalRepoId, name: "alpha-normal", worktrees: [worktree(repoId: normalRepoId)])
        let favoriteRepo = repo(
            id: favoriteRepoId,
            name: "zeta-favorite",
            isPinned: true,
            worktrees: [worktree(repoId: favoriteRepoId)]
        )
        let enrichmentByRepoId = [
            normalRepoId: resolvedRemote(repoId: normalRepoId, displayName: "alpha-normal"),
            favoriteRepoId: resolvedRemote(repoId: favoriteRepoId, displayName: "zeta-favorite"),
        ]

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [favoriteRepo, normalRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                query: ""
            )
        )

        #expect(projection.resolvedGroups.map(\.repoTitle) == ["zeta-favorite", "alpha-normal"])
        #expect(projection.resolvedGroups.flatMap(\.repos).map(\.id) == [favoriteRepoId, normalRepoId])
        #expect(projection.emptyState == .content)
    }

    @Test("favorites-first projection composes with search and pane grouping")
    func favoritesFirstProjectionComposesWithSearchAndPaneGrouping() {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalRepo = repo(id: normalRepoId, name: "alpha-target", worktrees: [worktree(repoId: normalRepoId)])
        let favoriteRepo = repo(
            id: favoriteRepoId,
            name: "zeta-target",
            isPinned: true,
            worktrees: [worktree(repoId: favoriteRepoId, name: "target-work")]
        )
        let favoriteWorktree = favoriteRepo.worktrees[0]
        let favoritePaneId = UUID()
        let favoriteTabId = UUID()
        let enrichmentByRepoId = [
            normalRepoId: resolvedRemote(repoId: normalRepoId, displayName: "alpha-target"),
            favoriteRepoId: resolvedRemote(repoId: favoriteRepoId, displayName: "zeta-target"),
        ]

        let matchingProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                surface: .panes,
                groupingMode: .repo,
                query: "target",
                paneLocationsByWorktreeId: [
                    favoriteWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: favoritePaneId,
                            tabId: favoriteTabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ]
            )
        )
        let noMatchProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                surface: .panes,
                groupingMode: .repo,
                query: "missing"
            )
        )

        #expect(matchingProjection.resolvedGroups.map(\.id) == ["panes:panes:repo:\(favoriteRepoId.uuidString)"])
        #expect(matchingProjection.resolvedGroups.first?.repos.map(\.id) == [favoriteRepoId])
        #expect(noMatchProjection.resolvedGroups.isEmpty)
        #expect(noMatchProjection.emptyState == .searchNoResults)
    }

    @Test("favorites-first projection partitions loading repos by favorite state")
    func favoritesFirstProjectionPartitionsLoadingReposByFavoriteState() {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalRepo = repo(id: normalRepoId, name: "alpha-loading", worktrees: [worktree(repoId: normalRepoId)])
        let favoriteRepo = repo(
            id: favoriteRepoId,
            name: "zeta-loading",
            isPinned: true,
            worktrees: [worktree(repoId: favoriteRepoId)]
        )
        let enrichmentByRepoId = [
            normalRepoId: RepoEnrichment.awaitingOrigin(repoId: normalRepoId),
            favoriteRepoId: RepoEnrichment.awaitingOrigin(repoId: favoriteRepoId),
        ]

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                query: ""
            )
        )

        #expect(projection.resolvedGroups.isEmpty)
        #expect(projection.loadingRepos.map(\.id) == [favoriteRepoId, normalRepoId])
        #expect(projection.sections.map(\.kind) == [.pinnedRepositories, .repositories])
        #expect(projection.sections[0].loadingRepos.map(\.id) == [favoriteRepoId])
        #expect(projection.sections[1].loadingRepos.map(\.id) == [normalRepoId])
        #expect(projection.emptyState == .content)
    }

    @Test("non-favorites remain visible without a favorite-specific empty state")
    func nonFavoritesRemainVisibleWithoutFavoriteSpecificEmptyState() {
        let repoId = UUID()
        let nonFavoriteRepo = repo(id: repoId, name: "alpha-normal", worktrees: [worktree(repoId: repoId)])
        let enrichmentByRepoId = [repoId: resolvedRemote(repoId: repoId, displayName: "alpha-normal")]

        let emptyFavoritesProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [nonFavoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                query: ""
            )
        )
        let noResultsProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [nonFavoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                query: "missing"
            )
        )

        #expect(emptyFavoritesProjection.emptyState == .content)
        #expect(emptyFavoritesProjection.showsNoResults == false)
        #expect(noResultsProjection.emptyState == .searchNoResults)
        #expect(noResultsProjection.showsNoResults)
    }

    @Test("row index expands an unseen group and resolves its worktree rows")
    func rowIndexExpandsUnseenGroupAndResolvesWorktreeRows() {
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
        let projection = RepoExplorerSidebarProjection.ready(
            RepoExplorerSidebarContent(
                sections: [
                    RepoExplorerSidebarSection(
                        kind: .repositories,
                        resolvedGroups: [group],
                        loadingRepos: []
                    )
                ],
                resolvedGroups: [group],
                loadingRepos: [],
                showsNoResults: false
            )
        )
        let index = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )

        #expect(index.entries.count == 4)
        guard index.entries.count > 2 else { return }
        guard case .resolvedWorktreeRow(let groupId, let indexedRepoId, let worktreeId, let rowId) = index.entries[2]
        else {
            Issue.record("Expected first projected worktree row after group header")
            return
        }

        let context = index.resolve(groupId: groupId, repoId: indexedRepoId, worktreeId: worktreeId, rowId: rowId)
        #expect(context?.group.id == group.id)
        #expect(context?.repo.id == repo.id)
        #expect(context?.worktree.id == feature.id)
    }

    @Test("row index flattens favorites and repositories section headers without changing group ids")
    func rowIndexFlattensFavoriteSectionsWithoutChangingGroupIds() {
        let favoriteRepoId = UUIDv7.generate()
        let normalRepoId = UUIDv7.generate()
        let favoriteRepo = repo(
            id: favoriteRepoId,
            name: "zeta-favorite",
            isPinned: true,
            worktrees: [worktree(repoId: favoriteRepoId)]
        )
        let normalRepo = repo(
            id: normalRepoId,
            name: "alpha-normal",
            worktrees: [worktree(repoId: normalRepoId)]
        )
        let favoriteGroup = RepoPresentationGroup(
            id: "repo:\(favoriteRepoId.uuidString)",
            repoTitle: favoriteRepo.name,
            organizationName: nil,
            repos: [favoriteRepo]
        )
        let normalGroup = RepoPresentationGroup(
            id: "repo:\(normalRepoId.uuidString)",
            repoTitle: normalRepo.name,
            organizationName: nil,
            repos: [normalRepo]
        )
        let projection = RepoExplorerSidebarProjection.ready(
            RepoExplorerSidebarContent(
                sections: [
                    RepoExplorerSidebarSection(
                        kind: .pinnedRepositories,
                        resolvedGroups: [favoriteGroup],
                        loadingRepos: []
                    ),
                    RepoExplorerSidebarSection(
                        kind: .repositories,
                        resolvedGroups: [normalGroup],
                        loadingRepos: []
                    ),
                ],
                resolvedGroups: [favoriteGroup, normalGroup],
                loadingRepos: [],
                emptyState: .content
            )
        )

        let index = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [favoriteGroup.id, normalGroup.id],
            isFiltering: false
        )
        #expect(
            index.entries.map(\.id) == [
                .sectionHeader(.pinnedRepositories),
                .group(groupID: favoriteGroup.id),
                .sectionHeader(.repositories),
                .group(groupID: normalGroup.id),
            ])
    }
}
