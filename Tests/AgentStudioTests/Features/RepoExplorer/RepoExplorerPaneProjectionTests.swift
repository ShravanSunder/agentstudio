import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorer pane projection")
struct RepoExplorerPaneProjectionTests {
    @Test("All Panes rows are complete worker values sorted by recency")
    func allPanesRowsCarryPresentationFactsInRecencyOrder() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId, name: "agent-studio.sidebar-grouping")
        let olderPaneId = UUIDv7.generate()
        let newerPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let snapshot = RepoExplorerSnapshot(
            repos: [makeRepo(id: repoId, worktrees: [worktree])],
            repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
            groupingMode: .pane,
            query: "",
            paneLocationsByWorktreeId: [
                worktree.id: [
                    .init(
                        paneId: olderPaneId,
                        tabId: tabId,
                        tabIndex: 0,
                        paneIndexInTab: 0,
                        isActiveInTab: false
                    ),
                    .init(
                        paneId: newerPaneId,
                        tabId: tabId,
                        tabIndex: 0,
                        paneIndexInTab: 1,
                        isActiveInTab: true
                    ),
                ]
            ]
        )

        let projection = RepoExplorerProjection.project(
            snapshot,
            paneRowFactsByPaneId: [
                olderPaneId: .init(
                    terminalTitle: "old shell",
                    recencyReferenceDate: Date(timeIntervalSince1970: 10),
                    recencyText: "2m",
                    isActive: false
                ),
                newerPaneId: .init(
                    terminalTitle: "tests running",
                    recencyReferenceDate: Date(timeIntervalSince1970: 20),
                    recencyText: "Now",
                    isActive: true
                ),
            ]
        )

        let group = try #require(projection.resolvedGroups.first)
        let rows = try #require(projection.paneRowsByGroupId[group.id])
        #expect(rows.map(\.destination.paneId) == [newerPaneId, olderPaneId])
        #expect(rows[0].primaryText == "agent-studio.sidebar-grouping · Pane 2")
        #expect(rows[0].secondaryText == "tests running")
        #expect(rows[0].recencyText == "Now")
        #expect(rows[0].isActive)
    }

    @Test("All Panes orders never-focused panes by the recency date used for display")
    func allPanesOrdersNeverFocusedPanesByDisplayedRecency() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let neverFocusedPaneId = UUIDv7.generate()
        let previouslyFocusedPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [makeRepo(id: repoId, worktrees: [worktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        .init(
                            paneId: neverFocusedPaneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        ),
                        .init(
                            paneId: previouslyFocusedPaneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 1,
                            isActiveInTab: false
                        ),
                    ]
                ]
            ),
            paneRowFactsByPaneId: [
                neverFocusedPaneId: .init(
                    terminalTitle: "new pane",
                    recencyReferenceDate: Date(timeIntervalSince1970: 20),
                    recencyText: "Now",
                    isActive: true
                ),
                previouslyFocusedPaneId: .init(
                    terminalTitle: "old pane",
                    recencyReferenceDate: Date(timeIntervalSince1970: 10),
                    recencyText: "5m",
                    isActive: false
                ),
            ]
        )

        let group = try #require(projection.resolvedGroups.first)
        let rows = try #require(projection.paneRowsByGroupId[group.id])
        #expect(rows.map(\.destination.paneId) == [neverFocusedPaneId, previouslyFocusedPaneId])
    }

    @Test("By Tab uses display titles, pane counts, tab order, and pane rows")
    func byTabProjectsPaneRowsUnderDisplayTitleHeaders() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let firstTabId = UUIDv7.generate()
        let secondTabId = UUIDv7.generate()
        let firstPaneId = UUIDv7.generate()
        let secondPaneId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [makeRepo(id: repoId, worktrees: [worktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        .init(
                            paneId: secondPaneId,
                            tabId: secondTabId,
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: false
                        ),
                        .init(
                            paneId: firstPaneId,
                            tabId: firstTabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        ),
                    ]
                ]
            ),
            paneRowFactsByPaneId: [
                firstPaneId: .init(
                    terminalTitle: "first terminal",
                    recencyReferenceDate: Date(timeIntervalSince1970: 10),
                    recencyText: "Now",
                    isActive: true
                ),
                secondPaneId: .init(
                    terminalTitle: "second terminal",
                    recencyReferenceDate: Date(timeIntervalSince1970: 20),
                    recencyText: "Now",
                    isActive: false
                ),
            ],
            tabGroupFactsByTabId: [
                firstTabId: .init(displayTitle: "Implementation"),
                secondTabId: .init(displayTitle: "Tests"),
            ]
        )

        #expect(projection.resolvedGroups.map(\.repoTitle) == ["Implementation", "Tests"])
        #expect(projection.resolvedGroups.map(\.organizationName) == ["1 pane", "1 pane"])
        #expect(projection.worktreeRowsByGroupId.isEmpty)
        #expect(projection.resolvedGroups.allSatisfy { projection.paneRowsByGroupId[$0.id]?.count == 1 })
    }

    @Test("recency text changes only at minute boundaries")
    func recencyTextUsesCoarseMinuteBuckets() {
        let lastInteraction = Date(timeIntervalSince1970: 100)
        #expect(
            RepoExplorerPaneRecencyText.display(
                lastInteractedAt: lastInteraction,
                now: Date(timeIntervalSince1970: 161)
            ) == "1m"
        )
        #expect(
            RepoExplorerPaneRecencyText.display(
                lastInteractedAt: lastInteraction,
                now: Date(timeIntervalSince1970: 199)
            ) == "1m"
        )
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
