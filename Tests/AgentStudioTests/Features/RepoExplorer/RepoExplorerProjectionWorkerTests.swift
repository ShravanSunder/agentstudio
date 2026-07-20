import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoExplorerProjectionWorker")
struct RepoExplorerProjectionWorkerTests {
    private enum CancellationProbe: Error {
        case cancelled
    }

    @Test("worker projects sidebar model and row index off caller isolation")
    func workerProjectsSidebarModelAndRowIndex() async throws {
        let repoId = UUID()
        let matchingWorktree = Worktree(
            repoId: repoId,
            name: "feature",
            path: URL(fileURLWithPath: "/tmp/feature"),
            isMainWorktree: false
        )
        let filteredWorktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/main"),
            isMainWorktree: true
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [filteredWorktree, matchingWorktree]
        )
        let snapshot = RepoExplorerSnapshot(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repoId: .resolvedRemote(
                    repoId: repoId,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:askluna/agent-studio",
                        remoteSlug: "askluna/agent-studio",
                        organizationName: "askluna",
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            ],
            groupingMode: .repo,
            sortOrder: .ascending,
            query: "feature"
        )
        let request = RepoExplorerProjectionRequest(
            generation: 3,
            snapshot: snapshot,
            expandedGroupIds: [],
            isFiltering: true,
            trigger: .search
        )

        let result = try await RepoExplorerProjectionWorker().project(request)

        #expect(result.generation == 3)
        #expect(result.snapshot == snapshot)
        #expect(result.trigger == .search)
        #expect(result.rowIndex.entries.count == 2)
        let visibleWorktreeIds = result.projection.resolvedGroups.first?.repos.first?.worktrees.map { $0.id }
        #expect(visibleWorktreeIds == [matchingWorktree.id])
        #expect(result.branchNameByWorktreeId[matchingWorktree.id] == "Unknown branch")
    }

    @Test("worker carries visibility mode through snapshot and filters off caller isolation")
    func workerCarriesVisibilityModeAndFilters() async throws {
        let normalRepoId = UUID()
        let favoriteRepoId = UUID()
        let normalRepo = repo(id: normalRepoId, name: "alpha-normal")
        let favoriteRepo = repo(id: favoriteRepoId, name: "zeta-favorite", isFavorite: true)
        let snapshot = RepoExplorerSnapshot(
            repos: [normalRepo, favoriteRepo],
            repoEnrichmentByRepoId: [
                normalRepoId: resolvedRemote(repoId: normalRepoId, displayName: "alpha-normal"),
                favoriteRepoId: resolvedRemote(repoId: favoriteRepoId, displayName: "zeta-favorite"),
            ],
            groupingMode: .repo,
            sortOrder: .ascending,
            visibilityMode: .favoritesOnly,
            query: ""
        )
        let request = RepoExplorerProjectionRequest(
            generation: 4,
            snapshot: snapshot,
            expandedGroupIds: [],
            isFiltering: false,
            trigger: .visibilityMode
        )

        let result = try await RepoExplorerProjectionWorker().project(request)

        #expect(result.generation == 4)
        #expect(result.snapshot.visibilityMode == .favoritesOnly)
        #expect(result.projection.resolvedGroups.map(\.repoTitle) == ["zeta-favorite"])
        #expect(result.projection.resolvedGroups.first?.repos.map(\.id) == [favoriteRepoId])
        #expect(result.rowIndex.entries.count == 1)
    }

    @Test("projection checks cancellation periodically within placement work")
    func projectionChecksCancellationWithinPlacementWork() {
        let repoId = UUID()
        let worktrees = (0..<600).map { index in
            Worktree(
                repoId: repoId,
                name: "worktree-\(index)",
                path: URL(fileURLWithPath: "/tmp/worktree-\(index)")
            )
        }
        let snapshot = RepoExplorerSnapshot(
            repos: [
                RepoPresentationItem(
                    id: repoId,
                    name: "agent-studio",
                    repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                    stableKey: "agent-studio",
                    worktrees: worktrees
                )
            ],
            repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId, displayName: "agent-studio")],
            groupingMode: .pane,
            query: "",
            paneLocationsByWorktreeId: Dictionary(
                uniqueKeysWithValues: worktrees.map { worktree in
                    (
                        worktree.id,
                        [
                            WorkspacePaneLocation(
                                paneId: UUID(),
                                tabId: UUID(),
                                tabIndex: 0,
                                paneIndexInTab: 0,
                                isActiveInTab: true
                            )
                        ]
                    )
                }
            )
        )
        var checkpointCount = 0

        #expect(throws: CancellationProbe.cancelled) {
            _ = try RepoExplorerProjection.projectCancellable(snapshot) {
                checkpointCount += 1
                if checkpointCount == 3 { throw CancellationProbe.cancelled }
            }
        }
        #expect(checkpointCount == 3)
    }

    private func repo(id: UUID, name: String, isFavorite: Bool = false) -> RepoPresentationItem {
        RepoPresentationItem(
            id: id,
            name: name,
            repoPath: URL(fileURLWithPath: "/tmp/\(name)"),
            stableKey: name,
            isFavorite: isFavorite,
            worktrees: [
                Worktree(
                    repoId: id,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/\(name)"),
                    isMainWorktree: true
                )
            ]
        )
    }

    private func resolvedRemote(repoId: UUID, displayName: String) -> RepoEnrichment {
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
