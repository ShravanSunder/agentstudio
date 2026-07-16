import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoExplorer read models")
struct RepoExplorerReadModelTests {
    @Test("grouping modes are exactly repo pane and tab")
    func groupingModesAreExactlyRepoPaneAndTab() {
        #expect(RepoExplorerGroupingMode.allCases == [.repo, .pane, .tab])
        #expect(RepoExplorerGroupingMode.allCases.map(\.title) == ["Repo", "Pane", "Tab"])
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

    @Test("favorites do not reorder normal repo pane and tab modes")
    func favoritesDoNotReorderNormalRepoPaneAndTabModes() {
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

        #expect(repoProjection.resolvedGroups.map(\.repoTitle) == ["alpha-normal", "zeta-favorite"])
        #expect(paneProjection.resolvedGroups.first?.id == "pane:\(firstPaneId.uuidString)")
        #expect(paneProjection.resolvedGroups.last?.id == "pane:\(secondPaneId.uuidString)")
        #expect(paneProjection.resolvedGroups.first?.repos.map(\.id) == [normalRepoId])
        #expect(paneProjection.resolvedGroups.last?.repos.map(\.id) == [favoriteRepoId])
        #expect(tabProjection.resolvedGroups.first?.repos.map(\.id) == [normalRepoId, favoriteRepoId])
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

    @Test("favorites-only visibility filters resolved repos without changing all-mode order")
    func favoritesOnlyVisibilityFiltersResolvedRepos() {
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

        let allProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [favoriteRepo, normalRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                visibilityMode: .all,
                query: ""
            )
        )
        let favoritesProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [favoriteRepo, normalRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                visibilityMode: .favoritesOnly,
                query: ""
            )
        )

        #expect(allProjection.resolvedGroups.map(\.repoTitle) == ["alpha-normal", "zeta-favorite"])
        #expect(favoritesProjection.resolvedGroups.map(\.repoTitle) == ["zeta-favorite"])
        #expect(favoritesProjection.resolvedGroups.first?.repos.map(\.id) == [favoriteRepoId])
        #expect(favoritesProjection.emptyState == .content)
    }

    @Test("favorites-only visibility composes with search and pane grouping")
    func favoritesOnlyVisibilityComposesWithSearchAndPaneGrouping() {
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
                visibilityMode: .favoritesOnly,
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
                visibilityMode: .favoritesOnly,
                query: "missing"
            )
        )

        #expect(matchingProjection.resolvedGroups.map(\.id) == ["pane:\(favoritePaneId.uuidString)"])
        #expect(matchingProjection.resolvedGroups.first?.repos.map(\.id) == [favoriteRepoId])
        #expect(noMatchProjection.resolvedGroups.isEmpty)
        #expect(noMatchProjection.emptyState == .searchNoResults)
    }

    @Test("favorites-only visibility filters loading repos")
    func favoritesOnlyVisibilityFiltersLoadingRepos() {
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
                visibilityMode: .favoritesOnly,
                query: ""
            )
        )

        #expect(projection.resolvedGroups.isEmpty)
        #expect(projection.loadingRepos.map(\.id) == [favoriteRepoId])
        #expect(projection.emptyState == .content)
    }

    @Test("favorites-only empty state is distinct from search no-results")
    func favoritesOnlyEmptyStateIsDistinctFromSearchNoResults() {
        let repoId = UUID()
        let nonFavoriteRepo = repo(id: repoId, name: "alpha-normal", worktrees: [worktree(repoId: repoId)])
        let enrichmentByRepoId = [repoId: resolvedRemote(repoId: repoId, displayName: "alpha-normal")]

        let emptyFavoritesProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [nonFavoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                visibilityMode: .favoritesOnly,
                query: ""
            )
        )
        let noResultsProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [nonFavoriteRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                visibilityMode: .favoritesOnly,
                query: "alpha"
            )
        )

        #expect(emptyFavoritesProjection.emptyState == .favoritesOnlyEmpty)
        #expect(emptyFavoritesProjection.showsFavoritesEmptyState)
        #expect(emptyFavoritesProjection.showsNoResults == false)
        #expect(noResultsProjection.emptyState == .searchNoResults)
        #expect(noResultsProjection.showsNoResults)
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
        guard case .resolvedWorktreeRow(let groupId, let indexedRepoId, let worktreeId, let rowId) = index.entries[1]
        else {
            Issue.record("Expected main worktree row after group header")
            return
        }

        let context = index.resolve(groupId: groupId, repoId: indexedRepoId, worktreeId: worktreeId, rowId: rowId)
        #expect(context?.group.id == group.id)
        #expect(context?.repo.id == repo.id)
        #expect(context?.worktree.id == main.id)
    }

    @Test("repo mode groups by repo id instead of source-family metadata")
    func repoModeGroupsByRepoIdInsteadOfSourceFamilyMetadata() {
        let firstRepoId = UUID()
        let secondRepoId = UUID()
        let firstRepo = repo(id: firstRepoId, name: "agent-studio-a", worktrees: [worktree(repoId: firstRepoId)])
        let secondRepo = repo(id: secondRepoId, name: "agent-studio-b", worktrees: [worktree(repoId: secondRepoId)])

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

        #expect(
            projection.resolvedGroups.map(\.id).sorted()
                == [
                    "repo:\(firstRepoId.uuidString)",
                    "repo:\(secondRepoId.uuidString)",
                ].sorted())
        #expect(projection.resolvedGroups.allSatisfy { $0.repos.count == 1 })
    }

    @Test("pane mode groups active worktrees by pane and leaves inactive last")
    func paneModeGroupsActiveWorktreesByPaneAndLeavesInactiveLast() {
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

        #expect(projection.resolvedGroups.map(\.id) == ["pane:\(paneId.uuidString)", "pane:inactive"])
        #expect(projection.resolvedGroups.first?.repos.first?.worktrees.map(\.id) == [activeWorktree.id])
        #expect(projection.resolvedGroups.last?.repos.first?.worktrees.map(\.id) == [inactiveWorktree.id])
    }

    @Test("tab mode preserves duplicate worktree rows inside one tab")
    func tabModePreservesDuplicateWorktreeRowsInsideOneTab() {
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

        let group = try! #require(projection.resolvedGroups.first)
        #expect(group.id == "tab:\(tabId.uuidString)")
        #expect(group.repos.first?.worktrees.map(\.id) == [duplicateWorktree.id, duplicateWorktree.id])

        let rowIndex = RepoExplorerRowIndex(projection: projection, expandedGroupIds: [group.id], isFiltering: false)
        let rowIds = rowIndex.entries.compactMap { entry -> String? in
            guard case .resolvedWorktreeRow(_, _, _, let rowId) = entry else { return nil }
            return rowId
        }
        #expect(rowIds.count == 2)
        #expect(Set(rowIds).count == 2)
        #expect(rowIds.allSatisfy { $0.contains(":pane:") })

        let placementTexts = rowIndex.entries.compactMap { entry -> String? in
            guard case .resolvedWorktreeRow(let groupId, let rowRepoId, let worktreeId, let rowId) = entry else {
                return nil
            }
            return rowIndex.resolve(
                groupId: groupId,
                repoId: rowRepoId,
                worktreeId: worktreeId,
                rowId: rowId
            )?.placementContext?.displayText
        }
        #expect(placementTexts == ["Pane 1", "Pane 2 active"])
    }

    @Test("pane and tab rows preserve automatic repo checkout colors")
    func paneAndTabRowsPreserveAutomaticRepoCheckoutColors() throws {
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

        let paneRow = try #require(paneProjection.worktreeRowsByGroupId["pane:\(paneId.uuidString)"]?.first)
        let tabRow = try #require(tabProjection.worktreeRowsByGroupId["tab:\(tabId.uuidString)"]?.first)
        let repoRow = try #require(
            repoProjection.worktreeRowsByGroupId["repo:\(secondRepoId.uuidString)"]?.first
        )
        #expect(repoRow.checkoutColorHex == expectedSecondRepoColor)
        #expect(paneRow.checkoutColorHex == expectedSecondRepoColor)
        #expect(tabRow.checkoutColorHex == expectedSecondRepoColor)
    }

    private func repo(
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

    private func worktree(repoId: UUID, name: String = "main", isMain: Bool = false) -> Worktree {
        Worktree(
            repoId: repoId,
            name: name,
            path: URL(fileURLWithPath: "/tmp/\(name)"),
            isMainWorktree: isMain
        )
    }

    private func resolvedRemote(repoId: UUID, displayName: String = "agent-studio") -> RepoEnrichment {
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
