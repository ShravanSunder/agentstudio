import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    @Test("Panes omits empty sections when the tab list is empty")
    func tabModeOmitsEmptySections() {
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                surface: .panes,
                groupingMode: .tab,
                query: ""
            )
        )

        #expect(projection.sections.isEmpty)

        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        #expect(rowIndex.entries.isEmpty)
    }

    @Test("repository-owned modes keep empty normal sections while By Tab keeps stored tab order")
    func groupingModesKeepTheirOwnedSectionShape() {
        let repoId = UUIDv7.generate()
        let favoriteWorktree = worktree(repoId: repoId)
        let favoriteRepository = repo(
            id: repoId,
            name: "favorite-repository",
            isPinned: true,
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
                    surface: .panes,
                    groupingMode: .repo,
                    query: "",
                    paneLocationsByWorktreeId: [favoriteWorktree.id: [location]]
                )
            ),
            RepoExplorerProjection.project(
                RepoExplorerSnapshot(
                    repos: [favoriteRepository],
                    repoEnrichmentByRepoId: enrichment,
                    surface: .panes,
                    groupingMode: .tab,
                    query: "",
                    paneLocationsByWorktreeId: [favoriteWorktree.id: [location]]
                )
            ),
        ]

        #expect(projections[0].sections.map(\.kind) == [.pinnedRepositories])
        #expect(projections[1].sections.map(\.kind) == [.panes])
        #expect(projections[2].sections.map(\.kind) == [.panes])
        #expect(
            projections[2].sections[0].resolvedGroups.map(\.id)
                == ["panes:panes:tab:\(tabId.uuidString)"]
        )
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
                isPinned: true,
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
                surface: .panes,
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

        #expect(projection.sections.map(\.kind) == [.panes])
        #expect(rowIndex.entries.first?.id == .sectionHeader(.panes))
        #expect(
            rowIndex.entries.dropFirst().allSatisfy { entry in
                if case .sectionHeader = entry.id { return false }
                return true
            }
        )
        let paneIdentities = rowIndex.entries.compactMap { entry -> RepoExplorerPaneListEntryIdentity? in
            guard case .resolvedPaneRow(_, let identity, _) = entry else { return nil }
            return identity
        }
        #expect(paneIdentities.count == 2)
        #expect(Set(paneIdentities.compactMap(\.repoId)) == [favoriteRepoId, regularRepoId])
        #expect(
            Set(paneIdentities.map(\.paneId))
                == Set(locations.values.flatMap { $0 }.map(\.paneId))
        )
        #expect(projection.resolvedGroups.map(\.id) == ["panes:panes:tab:\(tabId.uuidString)"])
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
                surface: .panes,
                groupingMode: .repo,
                query: "",
                paneLocationsByWorktreeId: [worktree.id: [location]]
            )
        )

        #expect(repoProjection.sections.map(\.kind) == [.repositories])
        #expect(paneProjection.sections.map(\.kind) == [.panes])
        #expect(repoProjection.sections.allSatisfy { $0.kind != .pinnedRepositories })
        #expect(paneProjection.sections.allSatisfy { $0.kind != .pinnedPanes })
    }

    @Test("empty ordinary partitions are omitted after pinned partitions")
    func emptyOrdinaryPartitionsAreOmittedAfterPinnedPartitions() {
        let repoId = UUIDv7.generate()
        let worktree = worktree(repoId: repoId)
        let repository = repo(
            id: repoId,
            name: "favorite-repository",
            isPinned: true,
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
                surface: .panes,
                groupingMode: .repo,
                query: "",
                paneLocationsByWorktreeId: [worktree.id: [location]]
            )
        )

        #expect(repoProjection.sections.map(\.kind) == [.pinnedRepositories])
        #expect(paneProjection.sections.map(\.kind) == [.panes])
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
            isPinned: true,
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

        #expect(projection.sections.map(\.kind) == [.pinnedRepositories])
        #expect(projection.loadingRepos.isEmpty)
        let groupId = "repos:pinnedRepositories:remote:askluna/\(favoriteRepo.name)"
        #expect(
            rowIndex.entries.map(\.id) == [
                .sectionHeader(.pinnedRepositories),
                .group(groupID: groupId),
                .worktree(
                    groupID: groupId,
                    repoID: favoriteId,
                    worktreeID: favoriteWorktree.id
                ),
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
                surface: .panes,
                groupingMode: .tab,
                query: ""
            )
        )
        let paneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: unresolvedRepos,
                repoEnrichmentByRepoId: enrichment,
                surface: .panes,
                groupingMode: .repo,
                query: ""
            )
        )

        #expect(tabProjection.loadingRepos.isEmpty)
        #expect(tabProjection.emptyState == .noPanes)
        #expect(paneProjection.loadingRepos.isEmpty)
        #expect(paneProjection.emptyState == .noPanes)

        let tabRowIndex = RepoExplorerRowIndex(projection: tabProjection, collapsedGroupIds: [], isFiltering: false)
        let paneRowIndex = RepoExplorerRowIndex(
            projection: paneProjection, collapsedGroupIds: [], isFiltering: false)

        #expect(tabRowIndex.entries.isEmpty)
        #expect(paneRowIndex.entries.isEmpty)
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
            isPinned: true,
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
                .sectionHeader(.pinnedRepositories),
                .loadingSectionHeader(.pinnedRepositories),
                .loadingRepository(section: .pinnedRepositories, repoID: favoriteId),
                .sectionHeader(.repositories),
                .loadingSectionHeader(.repositories),
                .loadingRepository(section: .repositories, repoID: repositoryId),
            ])
    }
}
