import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorer pane projection")
struct RepoExplorerPaneProjectionTests {
    @Test("pane grouping keeps validated associations in worktree buckets and isolates unassociated panes")
    func paneGroupingSeparatesAssociatedAndUnassociatedPanes() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let associatedPaneId = UUIDv7.generate()
        let nilAssociationPaneId = UUIDv7.generate()
        let danglingAssociationPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [makeRepo(id: repoId, worktrees: [worktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        WorkspacePaneLocation(
                            paneId: associatedPaneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ],
                unassociatedPaneLocations: [
                    WorkspacePaneLocation(
                        paneId: nilAssociationPaneId,
                        tabId: tabId,
                        tabIndex: 0,
                        paneIndexInTab: 1,
                        isActiveInTab: false
                    ),
                    WorkspacePaneLocation(
                        paneId: danglingAssociationPaneId,
                        tabId: tabId,
                        tabIndex: 0,
                        paneIndexInTab: 2,
                        isActiveInTab: false
                    ),
                ]
            )
        )

        #expect(projection.paneDestinationsByWorktreeId[worktree.id]?.map(\.paneId) == [associatedPaneId])
        #expect(projection.sections.map(\.kind) == [.panes, .ungrouped])
        let ungroupedSection = try #require(projection.sections.last)
        #expect(ungroupedSection.title == "Ungrouped")
        #expect(
            Set(ungroupedSection.unassociatedPaneDestinations.map(\.paneId))
                == [nilAssociationPaneId, danglingAssociationPaneId]
        )

        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        #expect(
            Set(
                rowIndex.entries.compactMap { entry -> UUID? in
                    guard case .unassociatedPaneRow(let destination) = entry else { return nil }
                    return destination.paneId
                }) == [nilAssociationPaneId, danglingAssociationPaneId]
        )
    }

    @Test("Ungrouped pane labels render without a worktree fallback")
    func ungroupedPaneLabelOmitsWorktreeFallback() {
        let destination = RepoExplorerUnassociatedPaneDestination(
            paneId: UUIDv7.generate(),
            tabId: UUIDv7.generate(),
            tabIndex: 1,
            paneIndexInTab: 2,
            isActiveInTab: true
        )

        #expect(destination.label(paneDisplayLabel: "Terminal") == "Terminal — Tab 2, Pane 3 — Active")
    }

    @Test("pane destinations sort by tab pane and stable pane identity")
    func paneDestinationsUseCanonicalLocationOrder() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let firstTiePaneId = try #require(UUID(uuidString: "00000000-0000-7000-8000-000000000001"))
        let secondTiePaneId = try #require(UUID(uuidString: "00000000-0000-7000-8000-000000000002"))
        let earlierTabPaneId = try #require(UUID(uuidString: "00000000-0000-7000-8000-000000000003"))
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [makeRepo(id: repoId, worktrees: [worktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        WorkspacePaneLocation(
                            paneId: secondTiePaneId,
                            tabId: UUIDv7.generate(),
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        ),
                        WorkspacePaneLocation(
                            paneId: earlierTabPaneId,
                            tabId: UUIDv7.generate(),
                            tabIndex: 0,
                            paneIndexInTab: 4,
                            isActiveInTab: true
                        ),
                        WorkspacePaneLocation(
                            paneId: firstTiePaneId,
                            tabId: UUIDv7.generate(),
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        ),
                    ]
                ]
            )
        )

        #expect(
            projection.paneDestinationsByWorktreeId[worktree.id]?.map(\.paneId)
                == [earlierTabPaneId, firstTiePaneId, secondTiePaneId]
        )
    }

    @Test("search filters visible leaves without filtering repository pane destinations")
    func searchDoesNotFilterRepositoryPaneDestinations() throws {
        let repoId = UUIDv7.generate()
        let matchingWorktree = makeWorktree(repoId: repoId, name: "matching")
        let hiddenWorktree = makeWorktree(repoId: repoId, name: "hidden")
        let matchingPaneId = UUIDv7.generate()
        let hiddenPaneId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [makeRepo(id: repoId, worktrees: [matchingWorktree, hiddenWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .repo,
                query: "matching",
                paneLocationsByWorktreeId: [
                    matchingWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: matchingPaneId,
                            tabId: UUIDv7.generate(),
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                    hiddenWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: hiddenPaneId,
                            tabId: UUIDv7.generate(),
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                ]
            )
        )

        let group = try #require(projection.resolvedGroups.first)
        #expect(group.repos.flatMap(\.worktrees).map(\.id) == [matchingWorktree.id])
        #expect(
            projection.paneDestinationsByRepoId[repoId]?.map(\.paneId)
                == [matchingPaneId, hiddenPaneId]
        )
    }

    @Test("pane search filters Ungrouped rows by their projected location label")
    func paneSearchFiltersUngroupedRows() throws {
        let paneId = UUIDv7.generate()
        let baseSnapshot = RepoExplorerSnapshot(
            repos: [],
            repoEnrichmentByRepoId: [:],
            groupingMode: .pane,
            query: "not-present",
            unassociatedPaneLocations: [
                WorkspacePaneLocation(
                    paneId: paneId,
                    tabId: UUIDv7.generate(),
                    tabIndex: 0,
                    paneIndexInTab: 1,
                    isActiveInTab: true
                )
            ]
        )

        let noMatch = RepoExplorerProjection.project(baseSnapshot)
        #expect(noMatch.sections.contains { $0.kind == .ungrouped } == false)
        #expect(noMatch.emptyState == .searchNoResults)

        let matching = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                groupingMode: .pane,
                query: "pane 2",
                unassociatedPaneLocations: baseSnapshot.unassociatedPaneLocations
            )
        )
        let ungrouped = try #require(matching.sections.first { $0.kind == .ungrouped })
        #expect(ungrouped.unassociatedPaneDestinations.map(\.paneId) == [paneId])
    }

    private func makeRepo(id: UUID, worktrees: [Worktree]) -> RepoPresentationItem {
        RepoPresentationItem(
            id: id,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: worktrees
        )
    }

    private func makeWorktree(repoId: UUID, name: String = "main") -> Worktree {
        Worktree(repoId: repoId, name: name, path: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func resolvedRemote(repoId: UUID) -> RepoEnrichment {
        .resolvedRemote(
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
    }
}
