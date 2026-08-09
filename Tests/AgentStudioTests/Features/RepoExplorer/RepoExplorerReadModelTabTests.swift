import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    @Test("tab section header remains explicit without nested partition labels")
    func tabSectionHeaderRemainsExplicitWithoutNestedPartitionLabels() {
        for isFavorite in [false, true] {
            let repoId = UUIDv7.generate()
            let tabId = UUIDv7.generate()
            let repository = repo(
                id: repoId,
                name: isFavorite ? "favorite" : "repository",
                isFavorite: isFavorite,
                worktrees: [worktree(repoId: repoId)]
            )
            let group = RepoPresentationGroup(
                id: "tab:\(tabId.uuidString)",
                repoTitle: "Tab 1",
                organizationName: nil,
                repos: [repository]
            )
            let projection = RepoExplorerSidebarProjection.ready(
                RepoExplorerSidebarContent(
                    sections: [
                        RepoExplorerSidebarSection(kind: .tabs, resolvedGroups: [group], loadingRepos: [])
                    ],
                    resolvedGroups: [group],
                    loadingRepos: [],
                    emptyState: .content
                )
            )

            let entries = RepoExplorerRowIndex(
                projection: projection,
                collapsedGroupIds: [],
                isFiltering: false
            ).entries

            #expect(entries.first?.id == "section-header:tabs")
            #expect(entries.count == 3)
        }
    }

    @Test("descending sort is preserved inside mixed favorite tab partitions")
    func descendingSortIsPreservedInsideMixedFavoriteTabPartitions() {
        let favoriteZuluId = UUIDv7.generate()
        let favoriteAlphaId = UUIDv7.generate()
        let repositoryYankeeId = UUIDv7.generate()
        let repositoryBravoId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let repositories = [
            repo(
                id: favoriteZuluId,
                name: "zulu-favorite",
                isFavorite: true,
                worktrees: [worktree(repoId: favoriteZuluId, name: "zulu")]
            ),
            repo(
                id: favoriteAlphaId,
                name: "alpha-favorite",
                isFavorite: true,
                worktrees: [worktree(repoId: favoriteAlphaId, name: "alpha")]
            ),
            repo(
                id: repositoryYankeeId,
                name: "yankee-repository",
                worktrees: [worktree(repoId: repositoryYankeeId, name: "yankee")]
            ),
            repo(
                id: repositoryBravoId,
                name: "bravo-repository",
                worktrees: [worktree(repoId: repositoryBravoId, name: "bravo")]
            ),
        ]
        let paneLocationsByWorktreeId = Dictionary(
            uniqueKeysWithValues: repositories.map { repository in
                (
                    repository.worktrees[0].id,
                    [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        )
                    ]
                )
            }
        )
        let enrichmentByRepoId = Dictionary(
            uniqueKeysWithValues: repositories.map { repository in
                (repository.id, resolvedRemote(repoId: repository.id, displayName: repository.name))
            }
        )

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .tab,
                sortOrder: .descending,
                query: "",
                paneLocationsByWorktreeId: paneLocationsByWorktreeId
            )
        )
        let tabGroup = projection.resolvedGroups[0]
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )

        #expect(tabGroup.repos.map(\.id) == [favoriteZuluId, favoriteAlphaId])
        #expect(projection.sections.map(\.kind) == [.favorites, .tabs])
        #expect(
            rowIndex.entries.map(\.id).prefix(2) == [
                "section-header:favorites",
                "group:tab:\(tabId.uuidString):favorites",
            ]
        )
        #expect(
            rowIndex.entries.compactMap { entry -> UUID? in
                guard case .resolvedWorktreeRow(_, let repoId, _, _) = entry else { return nil }
                return repoId
            } == [favoriteZuluId, favoriteAlphaId, repositoryYankeeId, repositoryBravoId]
        )
    }

    @Test("tab groups keep unique stored order and stable favorite partitions")
    func tabGroupsKeepUniqueStoredOrderAndStableFavoritePartitions() {
        let fixture = makeTabPartitionFixture()
        let projection = fixture.projection

        #expect(
            projection.resolvedGroups.map(\.id) == [
                "tab:\(fixture.laterTabId.uuidString):favorites",
                "tab:\(fixture.earlierTabId.uuidString):favorites",
                "tab:\(fixture.laterTabId.uuidString)",
                "tab:\(fixture.earlierTabId.uuidString)",
            ]
        )
        #expect(Set(projection.resolvedGroups.map(\.id)).count == 4)
        #expect(projection.sections.map(\.title) == ["Favorites", "Tabs"])

        let expectedRepoOrder = [
            fixture.betaFavoriteRepoId,
            fixture.zetaFavoriteRepoId,
            fixture.alphaNormalRepoId,
            fixture.gammaNormalRepoId,
        ]
        #expect(projection.resolvedGroups[0].repos.map(\.id) == Array(expectedRepoOrder.prefix(2)))
        #expect(projection.resolvedGroups[1].repos.map(\.id) == Array(expectedRepoOrder.prefix(2)))
        #expect(projection.resolvedGroups[2].repos.map(\.id) == Array(expectedRepoOrder.suffix(2)))
        #expect(projection.resolvedGroups[3].repos.map(\.id) == Array(expectedRepoOrder.suffix(2)))

        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        #expect(rowIndex.entries.first?.id == "section-header:favorites")
        let worktreeRowIds = rowIndex.entries.compactMap { entry -> String? in
            guard case .resolvedWorktreeRow(_, _, _, let rowId) = entry else { return nil }
            return rowId
        }
        #expect(worktreeRowIds.count == 8)
        #expect(Set(worktreeRowIds).count == worktreeRowIds.count)

        let tabWorktreeIdsByRepoId = Dictionary(
            uniqueKeysWithValues: fixture.repos.map { ($0.id, $0.worktrees[1].id) }
        )
        let earlierTabWorktreeIdsByRepoId = Dictionary(
            uniqueKeysWithValues: fixture.repos.map { ($0.id, $0.worktrees[0].id) }
        )
        let flattenedTabEntries = rowIndex.entries.compactMap { entry -> String? in
            switch entry {
            case .sectionHeader(let kind):
                return "section|\(kind.rawValue)"
            case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId, _):
                return "row|\(groupId)|\(repoId.uuidString)|\(worktreeId.uuidString)"
            default:
                return nil
            }
        }
        #expect(
            flattenedTabEntries
                == expectedTabEntries(
                    fixture: fixture,
                    tabWorktreeIdsByRepoId: tabWorktreeIdsByRepoId,
                    earlierTabWorktreeIdsByRepoId: earlierTabWorktreeIdsByRepoId
                )
        )
    }

    @Test("favorite and regular tab presentations keep independent disclosure state")
    func favoriteAndRegularTabPresentationsKeepIndependentDisclosureState() {
        let fixture = makeTabPartitionFixture()
        let favoriteGroupId = "tab:\(fixture.laterTabId.uuidString):favorites"
        let regularGroupId = "tab:\(fixture.laterTabId.uuidString)"

        let rowIndex = RepoExplorerRowIndex(
            projection: fixture.projection,
            collapsedGroupIds: [favoriteGroupId],
            isFiltering: false
        )
        let visibleRowGroupIds = rowIndex.entries.compactMap { entry -> String? in
            guard case .resolvedWorktreeRow(let groupId, _, _, _) = entry else { return nil }
            return groupId
        }

        #expect(!visibleRowGroupIds.contains(favoriteGroupId))
        #expect(visibleRowGroupIds.contains(regularGroupId))
    }

    @Test("favorite mutation uses the destination tab presentation disclosure state")
    func favoriteMutationUsesDestinationTabPresentationDisclosureState() {
        let fixture = makeTabPartitionFixture()
        let favoriteGroupId = "tab:\(fixture.laterTabId.uuidString):favorites"
        let regularGroupId = "tab:\(fixture.laterTabId.uuidString)"
        let favoriteRepoId = fixture.alphaNormalRepoId
        let updatedRepos = fixture.repos.map { repository in
            guard repository.id == favoriteRepoId else { return repository }
            return repo(
                id: repository.id,
                name: repository.name,
                isFavorite: true,
                worktrees: repository.worktrees
            )
        }
        let updatedProjection = makeTabProjection(
            repos: updatedRepos,
            earlierTabId: fixture.earlierTabId,
            laterTabId: fixture.laterTabId
        )

        let favoriteCollapsedRows = RepoExplorerRowIndex(
            projection: updatedProjection,
            collapsedGroupIds: [favoriteGroupId],
            isFiltering: false
        ).entries
        let regularCollapsedRows = RepoExplorerRowIndex(
            projection: updatedProjection,
            collapsedGroupIds: [regularGroupId],
            isFiltering: false
        ).entries
        let movedBackWithFavoriteCollapsedRows = RepoExplorerRowIndex(
            projection: fixture.projection,
            collapsedGroupIds: [favoriteGroupId],
            isFiltering: false
        ).entries
        let movedBackWithRegularCollapsedRows = RepoExplorerRowIndex(
            projection: fixture.projection,
            collapsedGroupIds: [regularGroupId],
            isFiltering: false
        ).entries

        #expect(!visibleGroupIds(for: favoriteRepoId, in: favoriteCollapsedRows).contains(favoriteGroupId))
        #expect(visibleGroupIds(for: favoriteRepoId, in: regularCollapsedRows).contains(favoriteGroupId))
        #expect(visibleGroupIds(for: favoriteRepoId, in: movedBackWithFavoriteCollapsedRows).contains(regularGroupId))
        #expect(!visibleGroupIds(for: favoriteRepoId, in: movedBackWithRegularCollapsedRows).contains(regularGroupId))
    }

    private struct TabPartitionFixture {
        let alphaNormalRepoId: UUID
        let betaFavoriteRepoId: UUID
        let gammaNormalRepoId: UUID
        let zetaFavoriteRepoId: UUID
        let earlierTabId: UUID
        let laterTabId: UUID
        let repos: [RepoPresentationItem]
        let projection: RepoExplorerSidebarProjection
    }

    private func makeTabPartitionFixture() -> TabPartitionFixture {
        let alphaNormalRepoId = UUIDv7.generate()
        let betaFavoriteRepoId = UUIDv7.generate()
        let gammaNormalRepoId = UUIDv7.generate()
        let zetaFavoriteRepoId = UUIDv7.generate()
        let earlierTabId = UUIDv7.generate()
        let laterTabId = UUIDv7.generate()
        let repos = [
            repoWithTabWorktrees(id: gammaNormalRepoId, name: "gamma-normal"),
            repoWithTabWorktrees(id: zetaFavoriteRepoId, name: "zeta-favorite", isFavorite: true),
            repoWithTabWorktrees(id: alphaNormalRepoId, name: "alpha-normal"),
            repoWithTabWorktrees(id: betaFavoriteRepoId, name: "beta-favorite", isFavorite: true),
        ]
        let projection = makeTabProjection(
            repos: repos,
            earlierTabId: earlierTabId,
            laterTabId: laterTabId
        )
        return TabPartitionFixture(
            alphaNormalRepoId: alphaNormalRepoId,
            betaFavoriteRepoId: betaFavoriteRepoId,
            gammaNormalRepoId: gammaNormalRepoId,
            zetaFavoriteRepoId: zetaFavoriteRepoId,
            earlierTabId: earlierTabId,
            laterTabId: laterTabId,
            repos: repos,
            projection: projection
        )
    }

    private func makeTabProjection(
        repos: [RepoPresentationItem],
        earlierTabId: UUID,
        laterTabId: UUID
    ) -> RepoExplorerSidebarProjection {
        var paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:]
        for repo in repos {
            paneLocationsByWorktreeId[repo.worktrees[0].id] = [
                WorkspacePaneLocation(
                    paneId: UUIDv7.generate(),
                    tabId: earlierTabId,
                    tabIndex: 2,
                    paneIndexInTab: 0,
                    isActiveInTab: false
                )
            ]
            paneLocationsByWorktreeId[repo.worktrees[1].id] = [
                WorkspacePaneLocation(
                    paneId: UUIDv7.generate(),
                    tabId: laterTabId,
                    tabIndex: 7,
                    paneIndexInTab: 0,
                    isActiveInTab: false
                )
            ]
        }
        let enrichmentByRepoId = Dictionary(
            uniqueKeysWithValues: repos.map { repo in
                (repo.id, resolvedRemote(repoId: repo.id, displayName: repo.name))
            }
        )
        return RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repos,
                repoEnrichmentByRepoId: enrichmentByRepoId,
                groupingMode: .tab,
                sortOrder: .ascending,
                query: "",
                paneLocationsByWorktreeId: paneLocationsByWorktreeId
            )
        )
    }

    private func visibleGroupIds(for matchingRepoId: UUID, in entries: [RepoExplorerListEntry]) -> Set<String> {
        Set(
            entries.compactMap { entry -> String? in
                guard case .resolvedWorktreeRow(let groupId, let repoId, _, _) = entry,
                    repoId == matchingRepoId
                else { return nil }
                return groupId
            })
    }

    private func expectedTabEntries(
        fixture: TabPartitionFixture,
        tabWorktreeIdsByRepoId: [UUID: UUID],
        earlierTabWorktreeIdsByRepoId: [UUID: UUID]
    ) -> [String] {
        [
            "section|favorites",
            "row|tab:\(fixture.laterTabId.uuidString):favorites|\(fixture.betaFavoriteRepoId.uuidString)|\(tabWorktreeIdsByRepoId[fixture.betaFavoriteRepoId]!.uuidString)",
            "row|tab:\(fixture.laterTabId.uuidString):favorites|\(fixture.zetaFavoriteRepoId.uuidString)|\(tabWorktreeIdsByRepoId[fixture.zetaFavoriteRepoId]!.uuidString)",
            "row|tab:\(fixture.earlierTabId.uuidString):favorites|\(fixture.betaFavoriteRepoId.uuidString)|\(earlierTabWorktreeIdsByRepoId[fixture.betaFavoriteRepoId]!.uuidString)",
            "row|tab:\(fixture.earlierTabId.uuidString):favorites|\(fixture.zetaFavoriteRepoId.uuidString)|\(earlierTabWorktreeIdsByRepoId[fixture.zetaFavoriteRepoId]!.uuidString)",
            "section|tabs",
            "row|tab:\(fixture.laterTabId.uuidString)|\(fixture.alphaNormalRepoId.uuidString)|\(tabWorktreeIdsByRepoId[fixture.alphaNormalRepoId]!.uuidString)",
            "row|tab:\(fixture.laterTabId.uuidString)|\(fixture.gammaNormalRepoId.uuidString)|\(tabWorktreeIdsByRepoId[fixture.gammaNormalRepoId]!.uuidString)",
            "row|tab:\(fixture.earlierTabId.uuidString)|\(fixture.alphaNormalRepoId.uuidString)|\(earlierTabWorktreeIdsByRepoId[fixture.alphaNormalRepoId]!.uuidString)",
            "row|tab:\(fixture.earlierTabId.uuidString)|\(fixture.gammaNormalRepoId.uuidString)|\(earlierTabWorktreeIdsByRepoId[fixture.gammaNormalRepoId]!.uuidString)",
        ]
    }
}
