import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    @Test("By Tab keeps its section header when the tab list is empty")
    func tabModeKeepsSectionHeaderWhenEmpty() {
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                groupingMode: .tab,
                query: ""
            )
        )

        #expect(projection.sections.map(\.kind) == [.tabs])

        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        #expect(rowIndex.entries.map(\.id) == ["section-header:tabs"])
    }

    @Test("repository-owned modes keep empty normal sections while By Tab keeps stored tab order")
    func groupingModesKeepTheirOwnedSectionShape() {
        let repoId = UUIDv7.generate()
        let favoriteWorktree = worktree(repoId: repoId)
        let favoriteRepository = repo(
            id: repoId,
            name: "favorite-repository",
            isFavorite: true,
            worktrees: [favoriteWorktree]
        )
        let tabId = UUIDv7.generate()
        let location = WorkspacePaneLocation(
            paneId: UUIDv7.generate(),
            tabId: tabId,
            tabIndex: 0,
            paneIndexInTab: 0,
            isActiveInTab: true
        )
        let enrichment = [repoId: resolvedRemote(repoId: repoId, displayName: favoriteRepository.name)]

        let projections = [
            RepoExplorerProjection.project(
                RepoExplorerSnapshot(
                    repos: [favoriteRepository],
                    repoEnrichmentByRepoId: enrichment,
                    groupingMode: .repo,
                    query: ""
                )
            ),
            RepoExplorerProjection.project(
                RepoExplorerSnapshot(
                    repos: [favoriteRepository],
                    repoEnrichmentByRepoId: enrichment,
                    groupingMode: .pane,
                    query: "",
                    paneLocationsByWorktreeId: [favoriteWorktree.id: [location]]
                )
            ),
            RepoExplorerProjection.project(
                RepoExplorerSnapshot(
                    repos: [favoriteRepository],
                    repoEnrichmentByRepoId: enrichment,
                    groupingMode: .tab,
                    query: "",
                    paneLocationsByWorktreeId: [favoriteWorktree.id: [location]]
                )
            ),
        ]

        #expect(projections[0].sections.map(\.kind) == [.favorites, .repositories])
        #expect(projections[1].sections.map(\.kind) == [.favorites, .panes])
        #expect(projections[2].sections.map(\.kind) == [.tabs])
        #expect(projections[0].sections.last?.resolvedGroups.isEmpty == true)
        #expect(projections[1].sections.last?.resolvedGroups.isEmpty == true)
        #expect(projections[2].sections[0].resolvedGroups.map(\.id) == ["tab:\(tabId.uuidString)"])
    }

    @Test("By Tab does not split panes by repository favorite state")
    func tabFavoritesDoNotPartitionPaneRows() {
        let favoriteRepoId = UUIDv7.generate()
        let regularRepoId = UUIDv7.generate()
        let favoriteWorktree = worktree(repoId: favoriteRepoId, name: "favorite")
        let regularWorktree = worktree(repoId: regularRepoId, name: "regular")
        let repositories = [
            repo(
                id: favoriteRepoId,
                name: "favorite-repository",
                isFavorite: true,
                worktrees: [favoriteWorktree]
            ),
            repo(id: regularRepoId, name: "regular-repository", worktrees: [regularWorktree]),
        ]
        let tabId = UUIDv7.generate()
        let locations = Dictionary(
            uniqueKeysWithValues: [favoriteWorktree, regularWorktree].enumerated().map { index, worktree in
                (
                    worktree.id,
                    [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: index,
                            isActiveInTab: index == 0
                        )
                    ]
                )
            }
        )
        let enrichment = Dictionary(
            uniqueKeysWithValues: repositories.map {
                ($0.id, resolvedRemote(repoId: $0.id, displayName: $0.name))
            }
        )

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: locations
            )
        )
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )

        #expect(projection.sections.map(\.kind) == [.tabs])
        #expect(rowIndex.entries.first?.id == "section-header:tabs")
        #expect(rowIndex.entries.allSatisfy { !$0.id.hasPrefix("group-section-header:") })
        #expect(
            rowIndex.entries.compactMap { entry -> UUID? in
                guard case .resolvedPaneRow(_, let identity, _) = entry else { return nil }
                return identity.repoId
            } == [favoriteRepoId, regularRepoId]
        )
        #expect(projection.resolvedGroups.map(\.id) == ["tab:\(tabId.uuidString)"])
    }

    @Test("repository-owned modes omit empty favorite partitions")
    func repositoryOwnedModesOmitEmptyFavoritePartitions() {
        let repoId = UUIDv7.generate()
        let worktree = worktree(repoId: repoId)
        let repository = repo(
            id: repoId,
            name: "alpha-repository",
            worktrees: [worktree]
        )
        let enrichment = [repoId: resolvedRemote(repoId: repoId, displayName: repository.name)]
        let location = WorkspacePaneLocation(
            paneId: UUIDv7.generate(),
            tabId: UUIDv7.generate(),
            tabIndex: 0,
            paneIndexInTab: 0,
            isActiveInTab: true
        )

        let repoProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .repo,
                query: ""
            )
        )
        let paneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [worktree.id: [location]]
            )
        )

        #expect(repoProjection.sections.map(\.kind) == [.repositories])
        #expect(paneProjection.sections.map(\.kind) == [.panes])
        #expect(repoProjection.sections.allSatisfy { $0.kind != .favorites })
        #expect(paneProjection.sections.allSatisfy { $0.kind != .favorites })
    }

    @Test("repository-owned modes keep empty normal partitions after favorites")
    func repositoryOwnedModesKeepEmptyNormalPartitionsAfterFavorites() {
        let repoId = UUIDv7.generate()
        let worktree = worktree(repoId: repoId)
        let repository = repo(
            id: repoId,
            name: "favorite-repository",
            isFavorite: true,
            worktrees: [worktree]
        )
        let enrichment = [repoId: resolvedRemote(repoId: repoId, displayName: repository.name)]
        let location = WorkspacePaneLocation(
            paneId: UUIDv7.generate(),
            tabId: UUIDv7.generate(),
            tabIndex: 0,
            paneIndexInTab: 0,
            isActiveInTab: true
        )

        let repoProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .repo,
                query: ""
            )
        )
        let paneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [worktree.id: [location]]
            )
        )

        #expect(repoProjection.sections.map(\.kind) == [.favorites, .repositories])
        #expect(paneProjection.sections.map(\.kind) == [.favorites, .panes])
        #expect(repoProjection.sections.last?.resolvedGroups.isEmpty == true)
        #expect(paneProjection.sections.last?.resolvedGroups.isEmpty == true)
    }

    @Test("search preserves the normal header while removing unmatched loading rows")
    func searchPreservesTheNormalHeaderWhileRemovingUnmatchedLoadingRows() {
        let favoriteId = UUIDv7.generate()
        let loadingId = UUIDv7.generate()
        let favoriteWorktree = worktree(repoId: favoriteId, name: "target")
        let loadingWorktree = worktree(repoId: loadingId, name: "loading")
        let favoriteRepo = repo(
            id: favoriteId,
            name: "favorite-target",
            isFavorite: true,
            worktrees: [favoriteWorktree]
        )
        let loadingRepo = repo(
            id: loadingId,
            name: "repository-loading",
            worktrees: [loadingWorktree]
        )

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [favoriteRepo, loadingRepo],
                repoEnrichmentByRepoId: [
                    favoriteId: resolvedRemote(repoId: favoriteId, displayName: favoriteRepo.name),
                    loadingId: .awaitingOrigin(repoId: loadingId),
                ],
                groupingMode: .repo,
                query: "target"
            )
        )
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: true
        )

        #expect(projection.sections.map(\.kind) == [.favorites, .repositories])
        #expect(projection.loadingRepos.isEmpty)
        #expect(
            rowIndex.entries.map(\.id) == [
                "section-header:favorites",
                "group:repo:\(favoriteId.uuidString)",
                "worktree:repo:\(favoriteId.uuidString):\(favoriteId.uuidString):\(favoriteWorktree.id.uuidString):inactive",
                "section-header:repositories",
            ])
    }

    @Test("By Tab and All Panes show the true empty state, never loading worktree rows, during a scan")
    func paneAndTabModesShowTrueEmptyStateDuringMassRegistrationScan() {
        // Reproduces the owner-reported defect: registering many worktrees while none are resolved yet
        // (and no panes/tabs exist) must never leak By-Repo loading placeholders into pane/tab-owned
        // sections. Contract item 3: By Tab/All Panes render panes only, plus item 13's true empty state.
        let unresolvedRepos = (0..<40).map { index -> RepoPresentationItem in
            repo(
                id: UUIDv7.generate(),
                name: "unresolved-repo-\(index)",
                worktrees: [worktree(repoId: UUIDv7.generate(), name: "unresolved-repo-\(index)")]
            )
        }
        let enrichment = Dictionary(
            uniqueKeysWithValues: unresolvedRepos.map { ($0.id, RepoEnrichment.awaitingOrigin(repoId: $0.id)) }
        )

        let tabProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: unresolvedRepos,
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .tab,
                query: ""
            )
        )
        let paneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: unresolvedRepos,
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .pane,
                query: ""
            )
        )

        #expect(tabProjection.loadingRepos.isEmpty)
        #expect(tabProjection.emptyState == .noTabs)
        #expect(paneProjection.loadingRepos.isEmpty)
        #expect(paneProjection.emptyState == .noPanes)

        let tabRowIndex = RepoExplorerRowIndex(projection: tabProjection, collapsedGroupIds: [], isFiltering: false)
        let paneRowIndex = RepoExplorerRowIndex(
            projection: paneProjection, collapsedGroupIds: [], isFiltering: false)

        #expect(tabRowIndex.entries.map(\.id) == ["section-header:tabs"])
        #expect(paneRowIndex.entries.map(\.id) == ["section-header:panes"])
        for entry in tabRowIndex.entries + paneRowIndex.entries {
            if case .loadingRepoRow = entry {
                Issue.record("By Tab/All Panes must never render a loading repo row: \(entry)")
            }
        }
    }

    @Test("loading rows flatten under their section scanning label")
    func loadingRowsFlattenUnderTheirSectionScanningLabel() {
        let favoriteId = UUIDv7.generate()
        let repositoryId = UUIDv7.generate()
        let favoriteRepo = repo(
            id: favoriteId,
            name: "favorite-loading",
            isFavorite: true,
            worktrees: [worktree(repoId: favoriteId)]
        )
        let repositoryRepo = repo(
            id: repositoryId,
            name: "repository-loading",
            worktrees: [worktree(repoId: repositoryId)]
        )
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [favoriteRepo, repositoryRepo],
                repoEnrichmentByRepoId: [
                    favoriteId: .awaitingOrigin(repoId: favoriteId),
                    repositoryId: .awaitingOrigin(repoId: repositoryId),
                ],
                groupingMode: .repo,
                query: ""
            )
        )
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )

        #expect(
            rowIndex.entries.map(\.id) == [
                "section-header:favorites",
                "loading-header:favorites",
                "loading-repo:favorites:\(favoriteId.uuidString)",
                "section-header:repositories",
                "loading-header:repositories",
                "loading-repo:repositories:\(repositoryId.uuidString)",
            ])
    }
}
