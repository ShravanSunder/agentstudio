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
            isFavorite: true,
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
        #expect(RepoExplorerGroupingMode.allCases == [.repo, .pane, .tab])
        #expect(RepoExplorerGroupingMode.allCases.map(\.title) == ["By Repo", "All Panes", "By Tab"])
        #expect(
            RepoExplorerGroupingMode.allCases.map(\.icon) == [
                .system(.folder),
                .system(.rectangleSplit2x1),
                .system(.rectangleStack),
            ])
    }

    @Test("sort order defaults ascending and can reverse repo groups")
    func sortOrderDefaultsAscendingAndCanReverseRepoGroups() {
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

        #expect(projection.resolvedGroups.map(\.repoTitle) == ["agent-browser", "actual-server"])
    }

    @Test("favorites are first in repository-owned modes and within each tab")
    func favoritesAreFirstInRepositoryOwnedModesAndWithinEachTab() {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalWorktree = worktree(repoId: normalRepoId, name: "z-normal")
        let favoriteWorktree = worktree(repoId: favoriteRepoId, name: "a-favorite")
        let normalRepo = repo(id: normalRepoId, name: "alpha-normal", worktrees: [normalWorktree])
        let favoriteRepo = repo(
            id: favoriteRepoId,
            name: "zeta-favorite",
            isFavorite: true,
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
                groupingMode: .pane,
                sortOrder: .ascending,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )
        let tabProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [normalRepo, favoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .tab,
                sortOrder: .ascending,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )

        #expect(repoProjection.resolvedGroups.map(\.repoTitle) == ["zeta-favorite", "alpha-normal"])
        #expect(repoProjection.sections.map(\.kind) == [.favorites, .repositories])
        #expect(repoProjection.sections.map(\.title) == ["Favorites", "Repositories"])
        #expect(repoProjection.sections[0].resolvedGroups.map(\.repoTitle) == ["zeta-favorite"])
        #expect(repoProjection.sections[1].resolvedGroups.map(\.repoTitle) == ["alpha-normal"])
        #expect(
            paneProjection.resolvedGroups.map(\.id) == [
                "pane-repo:\(favoriteRepoId.uuidString)",
                "pane-repo:\(normalRepoId.uuidString)",
            ]
        )
        #expect(paneProjection.resolvedGroups.first?.repos.map(\.id) == [favoriteRepoId])
        #expect(paneProjection.resolvedGroups.last?.repos.map(\.id) == [normalRepoId])
        #expect(paneProjection.sections.map(\.kind) == [.favorites, .panes])
        #expect(tabProjection.resolvedGroups.count == 1)
        #expect(tabProjection.resolvedGroups[0].repos.map(\.id) == [normalRepoId, favoriteRepoId])
        #expect(tabProjection.sections.map(\.kind) == [.tabs])
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
            isFavorite: true,
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
            isFavorite: true,
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
                groupingMode: .pane,
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
                groupingMode: .pane,
                query: "missing"
            )
        )

        #expect(matchingProjection.resolvedGroups.map(\.id) == ["pane-repo:\(favoriteRepoId.uuidString)"])
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
            isFavorite: true,
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
        #expect(projection.sections.map(\.kind) == [.favorites, .repositories])
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
            isFavorite: true,
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
                        kind: .favorites,
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
                .sectionHeader(.favorites),
                .group(groupID: favoriteGroup.id),
                .sectionHeader(.repositories),
                .group(groupID: normalGroup.id),
            ])
    }
}

extension RepoExplorerReadModelTests {
    @Test("repo mode combines distinct local checkouts with the same canonical remote identity")
    func repoModeGroupsByCanonicalRemoteIdentity() throws {
        let firstRepoId = UUID()
        let secondRepoId = UUID()
        let firstRepo = repo(
            id: firstRepoId,
            name: "agent-studio-a",
            worktrees: [worktree(repoId: firstRepoId, name: "agent-studio-a")]
        )
        let secondRepo = repo(
            id: secondRepoId,
            name: "agent-studio-b",
            worktrees: [worktree(repoId: secondRepoId, name: "agent-studio-b")]
        )

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [firstRepo, secondRepo],
                repoEnrichmentByRepoId: [
                    firstRepoId: resolvedRemote(repoId: firstRepoId, displayName: "agent-studio"),
                    secondRepoId: resolvedRemote(repoId: secondRepoId, displayName: "agent-studio"),
                ],
                groupingMode: .repo,
                query: ""
            )
        )

        let group = try #require(projection.resolvedGroups.first)
        #expect(projection.resolvedGroups.count == 1)
        #expect(Set(group.repos.map(\.id)) == Set([firstRepoId, secondRepoId]))
    }

    @Test("pane mode groups exact pane leaves by repo and omits inactive worktrees")
    func paneModeGroupsExactPaneLeavesByRepoAndOmitsInactiveWorktrees() throws {
        let repoId = UUID()
        let activeWorktree = worktree(repoId: repoId, name: "feature")
        let inactiveWorktree = worktree(repoId: repoId, name: "inactive")
        let paneId = UUID()
        let tabId = UUID()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [activeWorktree, inactiveWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    activeWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: paneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ]
            )
        )

        let expectedGroupId = "pane-repo:\(repoId.uuidString)"
        #expect(projection.resolvedGroups.map(\.id) == [expectedGroupId])
        #expect(projection.worktreeRowsByGroupId.isEmpty)

        let paneRow = try #require(projection.paneRowsByGroupId[expectedGroupId]?.first)
        #expect(paneRow.repoId == repoId)
        #expect(paneRow.destination.paneId == paneId)
        #expect(paneRow.destination.worktreeId == activeWorktree.id)
        #expect(paneRow.destination.worktreeLabel == activeWorktree.name)
        #expect(paneRow.destination.tabId == tabId)
        #expect(paneRow.destination.tabIndex == 0)
        #expect(paneRow.destination.paneIndexInTab == 0)
        #expect(paneRow.destination.isActiveInTab)
        #expect(
            paneRow.destination.label(paneDisplayLabel: "Terminal")
                == "feature — Terminal — Tab 1, Pane 1 — Active"
        )
        #expect(projection.paneDestinationsByWorktreeId[inactiveWorktree.id] == nil)

        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        #expect(rowIndex.entries.count == 3)
        guard
            case .resolvedPaneRow(let groupId, let rowIdentity, let rowId) =
                rowIndex.entries[2]
        else {
            Issue.record("Expected exact pane row after section and repo headers")
            return
        }
        #expect(rowIdentity.worktreeId == activeWorktree.id)
        let context = rowIndex.resolvePane(
            groupId: groupId,
            repoId: rowIdentity.repoId,
            paneId: rowIdentity.paneId,
            rowId: rowId
        )
        #expect(context?.destination == paneRow.destination)
    }

    @Test("By Tab projects pane rows only for located worktrees")
    func tabModeProjectsPaneRowsOnlyForLocatedWorktrees() throws {
        let repoId = UUIDv7.generate()
        let locatedWorktree = worktree(repoId: repoId, name: "located")
        let worktreeWithoutPane = worktree(repoId: repoId, name: "without-pane")
        let paneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [locatedWorktree, worktreeWithoutPane])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    locatedWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: paneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        )
                    ]
                ]
            )
        )

        #expect(projection.resolvedGroups.map(\.id) == ["tab:\(tabId.uuidString)"])
        #expect(projection.worktreeRowsByGroupId.isEmpty)
        #expect(
            projection.paneRowsByGroupId["tab:\(tabId.uuidString)"]?.map(\.destination.worktreeId)
                == [locatedWorktree.id]
        )

        let rowIndex = RepoExplorerRowIndex(projection: projection, collapsedGroupIds: [], isFiltering: false)
        #expect(rowIndex.entries.count == 3)
        guard
            case .resolvedPaneRow(let groupId, let identity, let rowId) =
                rowIndex.entries[2]
        else {
            Issue.record("Expected one located pane row after the Tabs and tab headers")
            return
        }
        let context = try #require(
            rowIndex.resolvePane(
                groupId: groupId,
                repoId: identity.repoId,
                paneId: identity.paneId,
                rowId: rowId
            )
        )
        #expect(context.destination.worktreeId == locatedWorktree.id)
        #expect(context.destination.paneId == paneId)
        #expect(context.destination.isActiveInTab == false)
    }

    @Test("By Tab preserves one pane row per pane on the same worktree")
    func tabModePreservesPaneRowsOnSameWorktree() throws {
        let repoId = UUID()
        let duplicateWorktree = worktree(repoId: repoId, name: "feature")
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let tabId = UUID()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [duplicateWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    duplicateWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: firstPaneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        ),
                        WorkspacePaneLocation(
                            paneId: secondPaneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 1,
                            isActiveInTab: true
                        ),
                    ]
                ]
            )
        )

        let group = try #require(projection.resolvedGroups.first)
        #expect(group.id == "tab:\(tabId.uuidString)")
        #expect(group.repos.first?.worktrees.map(\.id) == [duplicateWorktree.id])

        let rowIndex = RepoExplorerRowIndex(projection: projection, collapsedGroupIds: [], isFiltering: false)
        let rowIds = rowIndex.entries.compactMap { entry -> RepoExplorerRowID? in
            guard case .resolvedPaneRow(_, _, let rowId) = entry else { return nil }
            return rowId
        }
        #expect(rowIds.count == 2)
        #expect(Set(rowIds).count == 2)
        #expect(
            rowIds.allSatisfy { rowID in
                if case .associatedPane = rowID { return true }
                return false
            }
        )

        let paneIds = rowIndex.entries.compactMap { entry -> UUID? in
            guard case .resolvedPaneRow(let groupId, let identity, let rowId) = entry else {
                return nil
            }
            return rowIndex.resolvePane(
                groupId: groupId,
                repoId: identity.repoId,
                paneId: identity.paneId,
                rowId: rowId
            )?.destination.paneId
        }
        #expect(paneIds == [firstPaneId, secondPaneId])
    }

    @Test("pane groups preserve repository order independently from pane location order")
    func paneGroupsPreserveRepositoryOrder() {
        let firstRepoId = UUID()
        let secondRepoId = UUID()
        let laterWorktree = worktree(repoId: firstRepoId, name: "later")
        let earlierWorktree = worktree(repoId: secondRepoId, name: "earlier")
        let laterPaneId = UUID()
        let earlierPaneId = UUID()

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [
                    repo(id: firstRepoId, name: "alpha", worktrees: [laterWorktree]),
                    repo(id: secondRepoId, name: "beta", worktrees: [earlierWorktree]),
                ],
                repoEnrichmentByRepoId: [
                    firstRepoId: resolvedRemote(repoId: firstRepoId),
                    secondRepoId: resolvedRemote(repoId: secondRepoId),
                ],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    laterWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: laterPaneId,
                            tabId: UUID(),
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                    earlierWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: earlierPaneId,
                            tabId: UUID(),
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                ]
            )
        )

        #expect(
            projection.resolvedGroups.map(\.id) == [
                "pane-repo:\(firstRepoId.uuidString)",
                "pane-repo:\(secondRepoId.uuidString)",
            ]
        )
    }

    @Test("pane destinations and tab headers preserve stored workspace indices")
    func paneDestinationsAndTabHeadersPreserveStoredWorkspaceIndices() throws {
        let repoId = UUID()
        let worktree = worktree(repoId: repoId, name: "feature")
        let location = WorkspacePaneLocation(
            paneId: UUID(),
            tabId: UUID(),
            tabIndex: 6,
            paneIndexInTab: 3,
            isActiveInTab: true
        )
        let baseSnapshot = RepoExplorerSnapshot(
            repos: [repo(id: repoId, name: "agent-studio", worktrees: [worktree])],
            repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
            groupingMode: .pane,
            query: "",
            paneLocationsByWorktreeId: [worktree.id: [location]]
        )

        let paneProjection = RepoExplorerProjection.project(baseSnapshot)
        let paneDestination = try #require(paneProjection.paneDestinationsByWorktreeId[worktree.id]?.first)
        let tabSnapshot = RepoExplorerSnapshot(
            repos: baseSnapshot.repos,
            repoEnrichmentByRepoId: baseSnapshot.repoEnrichmentSnapshotByRepoId,
            groupingMode: .tab,
            sortOrder: baseSnapshot.sortOrder,
            query: baseSnapshot.query,
            paneLocationsByWorktreeId: baseSnapshot.paneLocationsByWorktreeId
        )
        let tabGroup = try #require(RepoExplorerProjection.project(tabSnapshot).resolvedGroups.first)

        #expect(
            paneDestination.label(paneDisplayLabel: "Terminal")
                == "feature — Terminal — Tab 7, Pane 4 — Active"
        )
        #expect(tabGroup.repoTitle == "Tab 7")
    }

    @Test("tab groups follow descending workspace location order")
    func tabGroupsFollowDescendingWorkspaceLocationOrder() {
        let repoId = UUID()
        let earlierWorktree = worktree(repoId: repoId, name: "earlier")
        let laterWorktree = worktree(repoId: repoId, name: "later")
        let earlierTabId = UUID()
        let laterTabId = UUID()

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [earlierWorktree, laterWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    earlierWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUID(),
                            tabId: earlierTabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                    laterWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUID(),
                            tabId: laterTabId,
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                ]
            )
        )

        #expect(
            projection.resolvedGroups.map(\.id) == [
                "tab:\(earlierTabId.uuidString)",
                "tab:\(laterTabId.uuidString)",
            ]
        )
    }

    @Test("repo rows preserve checkout colors while pane modes preserve repo containment")
    func repoRowsPreserveColorsAndPaneModesPreserveContainment() throws {
        let firstRepoId = UUID()
        let secondRepoId = UUID()
        let firstWorktree = worktree(repoId: firstRepoId, name: "first")
        let secondWorktree = worktree(repoId: secondRepoId, name: "second")
        let firstRepo = repo(id: firstRepoId, name: "actual-a", worktrees: [firstWorktree])
        let secondRepo = repo(id: secondRepoId, name: "actual-b", worktrees: [secondWorktree])
        let paneId = UUID()
        let tabId = UUID()
        let enrichmentByRepoId = [
            firstRepoId: resolvedRemote(repoId: firstRepoId, displayName: "actual"),
            secondRepoId: resolvedRemote(repoId: secondRepoId, displayName: "actual"),
        ]
        let sourceMetadata = RepoPresentationColoring.buildRepoMetadata(
            repos: [firstRepo, secondRepo],
            repoEnrichmentByRepoId: enrichmentByRepoId
        )
        let sourceGroup = try #require(
            RepoPresentationGrouping.buildGroups(
                repos: [firstRepo, secondRepo],
                metadataByRepoId: sourceMetadata
            ).first
        )
        let expectedSecondRepoColor = RepoPresentationColoring.checkoutColorHex(
            for: secondRepo,
            in: sourceGroup
        )
        let locationsByWorktreeId = [
            secondWorktree.id: [
                WorkspacePaneLocation(
                    paneId: paneId,
                    tabId: tabId,
                    tabIndex: 0,
                    paneIndexInTab: 0,
                    isActiveInTab: true
                )
            ]
        ]

        let paneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [firstRepo, secondRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )
        let tabProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [firstRepo, secondRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )
        let repoProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [firstRepo, secondRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .repo,
                query: ""
            )
        )

        let paneRow = try #require(
            paneProjection.paneRowsByGroupId["pane-repo:\(secondRepoId.uuidString)"]?.first
        )
        let tabRow = try #require(tabProjection.paneRowsByGroupId["tab:\(tabId.uuidString)"]?.first)
        let repoRow = try #require(
            repoProjection.worktreeRowsByGroupId.values
                .flatMap { $0 }
                .first { $0.repo.id == secondRepoId }
        )
        #expect(repoRow.checkoutColorHex == expectedSecondRepoColor)
        #expect(paneRow.repoId == secondRepoId)
        #expect(paneRow.destination.worktreeId == secondWorktree.id)
        #expect(tabRow.repoId == secondRepoId)
        #expect(tabRow.destination.worktreeId == secondWorktree.id)
    }

    func repo(
        id: UUID,
        name: String,
        isFavorite: Bool = false,
        worktrees: [Worktree]
    ) -> RepoPresentationItem {
        RepoPresentationItem(
            id: id,
            name: name,
            repoPath: URL(fileURLWithPath: "/tmp/\(name)"),
            stableKey: name,
            isFavorite: isFavorite,
            worktrees: worktrees
        )
    }

    func repoWithTabWorktrees(
        id: UUID,
        name: String,
        isFavorite: Bool = false
    ) -> RepoPresentationItem {
        repo(
            id: id,
            name: name,
            isFavorite: isFavorite,
            worktrees: [
                worktree(repoId: id, name: "\(name)-earlier"),
                worktree(repoId: id, name: "\(name)-later"),
            ]
        )
    }

    func worktree(repoId: UUID, name: String = "main", isMain: Bool = false) -> Worktree {
        Worktree(
            repoId: repoId,
            name: name,
            path: URL(fileURLWithPath: "/tmp/\(name)"),
            isMainWorktree: isMain
        )
    }

    func resolvedRemote(repoId: UUID, displayName: String = "agent-studio") -> RepoEnrichment {
        .resolvedRemote(
            repoId: repoId,
            raw: RawRepoOrigin(origin: "git@github.com:askluna/\(displayName).git", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:askluna/\(displayName)",
                remoteSlug: "askluna/\(displayName)",
                organizationName: "askluna",
                displayName: displayName
            ),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
