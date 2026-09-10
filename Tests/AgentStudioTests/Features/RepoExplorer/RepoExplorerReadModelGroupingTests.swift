import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    @Test("repo mode combines distinct local checkouts with the same canonical remote identity")
    func repoModeGroupsByCanonicalRemoteIdentity() throws {
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
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
        let repoId = UUIDv7.generate()
        let activeWorktree = worktree(repoId: repoId, name: "feature")
        let inactiveWorktree = worktree(repoId: repoId, name: "inactive")
        let paneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [activeWorktree, inactiveWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                surface: .panes,
                groupingMode: .repo,
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

        let expectedGroupId = "panes:panes:repo:\(repoId.uuidString)"
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
                surface: .panes,
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

        #expect(projection.resolvedGroups.map(\.id) == ["panes:panes:tab:\(tabId.uuidString)"])
        #expect(projection.worktreeRowsByGroupId.isEmpty)
        #expect(
            projection.paneRowsByGroupId["panes:panes:tab:\(tabId.uuidString)"]?.map(\.destination.worktreeId)
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
        let repoId = UUIDv7.generate()
        let duplicateWorktree = worktree(repoId: repoId, name: "feature")
        let firstPaneId = UUIDv7.generate()
        let secondPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [duplicateWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                surface: .panes,
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
        #expect(group.id == "panes:panes:tab:\(tabId.uuidString)")
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
                if case .tabPane = rowID { return true }
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
        #expect(paneIds.count == 2)
        #expect(Set(paneIds) == [firstPaneId, secondPaneId])
    }

    @Test("pane groups preserve repository order independently from pane location order")
    func paneGroupsPreserveRepositoryOrder() {
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let laterWorktree = worktree(repoId: firstRepoId, name: "later")
        let earlierWorktree = worktree(repoId: secondRepoId, name: "earlier")
        let laterPaneId = UUIDv7.generate()
        let earlierPaneId = UUIDv7.generate()

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
                surface: .panes,
                groupingMode: .repo,
                query: "",
                paneLocationsByWorktreeId: [
                    laterWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: laterPaneId,
                            tabId: UUIDv7.generate(),
                            tabIndex: 1,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                    earlierWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: earlierPaneId,
                            tabId: UUIDv7.generate(),
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
                "panes:panes:repo:\(firstRepoId.uuidString)",
                "panes:panes:repo:\(secondRepoId.uuidString)",
            ]
        )
    }

    @Test("pane destinations and tab headers preserve stored workspace indices")
    func paneDestinationsAndTabHeadersPreserveStoredWorkspaceIndices() throws {
        let repoId = UUIDv7.generate()
        let worktree = worktree(repoId: repoId, name: "feature")
        let location = WorkspacePaneLocation(
            paneId: UUIDv7.generate(),
            tabId: UUIDv7.generate(),
            tabIndex: 6,
            paneIndexInTab: 3,
            isActiveInTab: true
        )
        let baseSnapshot = RepoExplorerSnapshot(
            repos: [repo(id: repoId, name: "agent-studio", worktrees: [worktree])],
            repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
            surface: .panes,
            groupingMode: .repo,
            query: "",
            paneLocationsByWorktreeId: [worktree.id: [location]]
        )

        let paneProjection = RepoExplorerProjection.project(baseSnapshot)
        let paneDestination = try #require(paneProjection.paneDestinationsByWorktreeId[worktree.id]?.first)
        let tabSnapshot = RepoExplorerSnapshot(
            repos: baseSnapshot.repos,
            repoEnrichmentByRepoId: baseSnapshot.repoEnrichmentSnapshotByRepoId,
            surface: .panes,
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
        let repoId = UUIDv7.generate()
        let earlierWorktree = worktree(repoId: repoId, name: "earlier")
        let laterWorktree = worktree(repoId: repoId, name: "later")
        let earlierTabId = UUIDv7.generate()
        let laterTabId = UUIDv7.generate()

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [earlierWorktree, laterWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                surface: .panes,
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    earlierWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
                            tabId: earlierTabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ],
                    laterWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: UUIDv7.generate(),
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
                "panes:panes:tab:\(earlierTabId.uuidString)",
                "panes:panes:tab:\(laterTabId.uuidString)",
            ]
        )
    }

    @Test("repo rows preserve checkout colors while pane modes preserve repo containment")
    func repoRowsPreserveColorsAndPaneModesPreserveContainment() throws {
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let firstWorktree = worktree(repoId: firstRepoId, name: "first")
        let secondWorktree = worktree(repoId: secondRepoId, name: "second")
        let firstRepo = repo(id: firstRepoId, name: "actual-a", worktrees: [firstWorktree])
        let secondRepo = repo(id: secondRepoId, name: "actual-b", worktrees: [secondWorktree])
        let paneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
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
                surface: .panes,
                groupingMode: .repo,
                query: "",
                paneLocationsByWorktreeId: locationsByWorktreeId
            )
        )
        let tabProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [firstRepo, secondRepo],
                repoEnrichmentByRepoId: enrichmentByRepoId,
                surface: .panes,
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
            paneProjection.paneRowsByGroupId["panes:panes:repo:\(secondRepoId.uuidString)"]?.first
        )
        let tabRow = try #require(tabProjection.paneRowsByGroupId["panes:panes:tab:\(tabId.uuidString)"]?.first)
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

}
