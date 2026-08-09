import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
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
        #expect(paneProjection.sections.map(\.kind) == [.repositories])
        #expect(repoProjection.sections.allSatisfy { $0.kind != .favorites })
        #expect(paneProjection.sections.allSatisfy { $0.kind != .favorites })
    }

    @Test("repository-owned modes omit empty repository partitions")
    func repositoryOwnedModesOmitEmptyRepositoryPartitions() {
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

        #expect(repoProjection.sections.map(\.kind) == [.favorites])
        #expect(paneProjection.sections.map(\.kind) == [.favorites])
        #expect(repoProjection.sections.allSatisfy { $0.kind != .repositories })
        #expect(paneProjection.sections.allSatisfy { $0.kind != .repositories })
    }

    @Test("search removes empty partitions and their loading rows")
    func searchRemovesEmptyPartitionsAndTheirLoadingRows() {
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

        #expect(projection.sections.map(\.kind) == [.favorites])
        #expect(projection.loadingRepos.isEmpty)
        #expect(
            rowIndex.entries.map(\.id) == [
                "section-header:favorites",
                "group:repo:\(favoriteId.uuidString)",
                "worktree:repo:\(favoriteId.uuidString):\(favoriteId.uuidString):\(favoriteWorktree.id.uuidString):inactive",
            ])
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
