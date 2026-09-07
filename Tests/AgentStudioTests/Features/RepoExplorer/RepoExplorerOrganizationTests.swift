import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    @Test("whitespace-only query preserves collapsed groups through the worker")
    func whitespaceQueryPreservesCollapsedGroups() throws {
        let repoID = UUIDv7.generate()
        let repository = repo(id: repoID, name: "alpha", worktrees: [worktree(repoId: repoID)])
        let groupID = "repos:repositories:remote:askluna/alpha"
        let result = try RepoExplorerProjectionWorker.project(
            RepoExplorerProjectionRequest(
                generation: 1,
                snapshot: RepoExplorerSnapshot(
                    repos: [repository],
                    repoEnrichmentByRepoId: [repoID: resolvedRemote(repoId: repoID, displayName: "alpha")],
                    query: "  "
                ),
                collapsedGroupIds: [groupID], isFiltering: true, trigger: .search
            ))
        #expect(!result.rowIndex.isFiltering)
        #expect(result.rowIndex.entries.map(\.id) == [.sectionHeader(.repositories), .group(groupID: groupID)])
    }

    @Test("Panes membership does not depend on repository enrichment", arguments: RepoExplorerGroupingMode.allCases)
    func paneMembershipSurvivesPendingRepositoryEnrichment(groupingMode: RepoExplorerGroupingMode) {
        let repoID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let checkout = worktree(repoId: repoID)
        let repository = repo(id: repoID, name: "loading", worktrees: [checkout])
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository], repoEnrichmentByRepoId: [repoID: .awaitingOrigin(repoId: repoID)],
                surface: .panes, groupingMode: groupingMode, query: "",
                paneLocationsByWorktreeId: [checkout.id: [paneLocation(paneID: paneID, tabID: tabID)]]
            ),
            paneRowFactsByPaneId: [paneID: paneFacts(title: "Build")]
        )
        #expect(projection.paneRowsByGroupId.values.flatMap { $0 }.map { $0.destination.paneId } == [paneID])
        #expect(projection.loadingRepos.isEmpty)
    }

    private var organizationCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Repos and Panes partition independent pins and merge them without data loss")
    func surfacesPartitionIndependentPinsAndMergeWithoutDataLoss() throws {
        let pinnedRepoID = UUIDv7.generate()
        let ordinaryRepoID = UUIDv7.generate()
        let closedRepoID = UUIDv7.generate()
        let pinnedWorktree = worktree(repoId: pinnedRepoID, name: "pinned-worktree")
        let ordinaryWorktree = worktree(repoId: ordinaryRepoID, name: "ordinary-worktree")
        let closedWorktree = worktree(repoId: closedRepoID, name: "closed-worktree")
        let pinnedPaneID = UUIDv7.generate()
        let ordinaryPaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let repositories = [
            repo(id: pinnedRepoID, name: "pinned-repository", isPinned: true, worktrees: [pinnedWorktree]),
            repo(id: ordinaryRepoID, name: "ordinary-repository", worktrees: [ordinaryWorktree]),
            repo(id: closedRepoID, name: "closed-repository", worktrees: [closedWorktree]),
        ]
        let enrichment = Dictionary(
            uniqueKeysWithValues: repositories.map {
                ($0.id, resolvedRemote(repoId: $0.id, displayName: $0.name))
            }
        )
        let locations = [
            pinnedWorktree.id: [paneLocation(paneID: ordinaryPaneID, tabID: tabID, paneIndex: 0)],
            ordinaryWorktree.id: [paneLocation(paneID: pinnedPaneID, tabID: tabID, paneIndex: 1)],
        ]
        let paneFacts = [
            pinnedPaneID: paneFacts(title: "Pinned Pane", isPinned: true),
            ordinaryPaneID: paneFacts(title: "Ordinary Pane"),
        ]

        let reposWithPins = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: enrichment,
                surface: .repos,
                showsPinned: true,
                query: "",
                paneLocationsByWorktreeId: locations
            ),
            paneRowFactsByPaneId: paneFacts
        )
        let panesWithPins = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: enrichment,
                surface: .panes,
                groupingMode: .repo,
                showsPinned: true,
                query: "",
                paneLocationsByWorktreeId: locations
            ),
            paneRowFactsByPaneId: paneFacts
        )

        #expect(
            reposWithPins.sections.map(\.kind)
                == [.pinnedRepositories, .openRepositories, .repositories]
        )
        #expect(reposWithPins.sections[0].resolvedGroups.flatMap(\.repos).map(\.id) == [pinnedRepoID])
        #expect(reposWithPins.sections[1].resolvedGroups.flatMap(\.repos).map(\.id) == [ordinaryRepoID])
        #expect(reposWithPins.sections[2].resolvedGroups.flatMap(\.repos).map(\.id) == [closedRepoID])
        #expect(panesWithPins.sections.map(\.kind) == [.pinnedPanes, .panes])
        #expect(paneIDs(in: panesWithPins.sections[0], projection: panesWithPins) == [pinnedPaneID])
        #expect(paneIDs(in: panesWithPins.sections[1], projection: panesWithPins) == [ordinaryPaneID])

        let reposMerged = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: enrichment,
                surface: .repos,
                showsPinned: false,
                query: "",
                paneLocationsByWorktreeId: locations
            ),
            paneRowFactsByPaneId: paneFacts
        )
        let panesMerged = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repositories,
                repoEnrichmentByRepoId: enrichment,
                surface: .panes,
                groupingMode: .repo,
                showsPinned: false,
                query: "",
                paneLocationsByWorktreeId: locations
            ),
            paneRowFactsByPaneId: paneFacts
        )

        #expect(reposMerged.sections.map(\.kind) == [.openRepositories, .repositories])
        #expect(
            Set(reposMerged.sections.flatMap(\.resolvedGroups).flatMap(\.repos).map(\.id))
                == Set(repositories.map(\.id))
        )
        #expect(panesMerged.sections.map(\.kind) == [.panes])
        #expect(Set(paneIDs(in: panesMerged.sections[0], projection: panesMerged)) == [pinnedPaneID, ordinaryPaneID])
    }

    @Test("Panes grouping changes placement while preserving every canonical tab-owned destination")
    func paneGroupingMatrixPreservesDestinationsAndTabOwnership() throws {
        let now = Date(timeIntervalSince1970: 1_788_804_000)
        let repoID = UUIDv7.generate()
        let worktree = worktree(repoId: repoID, name: "main")
        let repoPaneID = UUIDv7.generate()
        let unassociatedPaneID = UUIDv7.generate()
        let laterTabID = UUIDv7.generate()
        let earlierTabID = UUIDv7.generate()
        let repository = repo(id: repoID, name: "repository", worktrees: [worktree])
        let snapshots = RepoExplorerGroupingMode.allCases.map { groupingMode in
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: [repoID: resolvedRemote(repoId: repoID, displayName: repository.name)],
                surface: .panes,
                groupingMode: groupingMode,
                referenceDate: now,
                calendar: organizationCalendar,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [paneLocation(paneID: repoPaneID, tabID: laterTabID, tabIndex: 1)]
                ],
                unassociatedPaneLocations: [
                    paneLocation(paneID: unassociatedPaneID, tabID: earlierTabID, tabIndex: 0)
                ]
            )
        }
        let facts = [
            repoPaneID: paneFacts(title: "Repository Pane", activityAt: now.addingTimeInterval(-30)),
            unassociatedPaneID: paneFacts(title: "Loose Pane"),
        ]

        let projections = snapshots.map {
            RepoExplorerProjection.project($0, paneRowFactsByPaneId: facts)
        }
        for projection in projections {
            let rows = projection.paneRowsByGroupId.values.flatMap { $0 }
            #expect(Set(rows.map { $0.destination.paneId }) == [repoPaneID, unassociatedPaneID])
            #expect(rows.allSatisfy { $0.membershipOwner == .tab })
        }

        #expect(
            projections[0].resolvedGroups.map(\.id)
                == [
                    "panes:panes:repo:unassociated",
                    "panes:panes:repo:\(repoID.uuidString)",
                ]
        )
        #expect(
            projections[1].resolvedGroups.map(\.id)
                == [
                    "panes:panes:tab:\(earlierTabID.uuidString)",
                    "panes:panes:tab:\(laterTabID.uuidString)",
                ]
        )
        #expect(projections[2].resolvedGroups.map(\.repoTitle) == ["Active", "No activity"])
    }

    @Test("activity subgroup rows are scoped to their group and main activity grouping suppresses them")
    func activitySubgroupRowsAreScopedAndSuppressedForMainActivityGrouping() throws {
        let now = Date(timeIntervalSince1970: 1_788_804_000)
        let repoID = UUIDv7.generate()
        let worktree = worktree(repoId: repoID, name: "main")
        let activePaneID = UUIDv7.generate()
        let quietPaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let repository = repo(id: repoID, name: "repository", worktrees: [worktree])
        let base = RepoExplorerSnapshot(
            repos: [repository],
            repoEnrichmentByRepoId: [repoID: resolvedRemote(repoId: repoID, displayName: repository.name)],
            surface: .panes,
            groupingMode: .repo,
            subgroupMode: .activity,
            referenceDate: now,
            calendar: organizationCalendar,
            query: "",
            paneLocationsByWorktreeId: [
                worktree.id: [
                    paneLocation(paneID: activePaneID, tabID: tabID, paneIndex: 0),
                    paneLocation(paneID: quietPaneID, tabID: tabID, paneIndex: 1),
                ]
            ]
        )
        let facts = [
            activePaneID: paneFacts(title: "Active", activityAt: now.addingTimeInterval(-30)),
            quietPaneID: paneFacts(title: "Quiet"),
        ]

        let subgroupProjection = RepoExplorerProjection.project(base, paneRowFactsByPaneId: facts)
        let subgroupIndex = RepoExplorerRowIndex(
            projection: subgroupProjection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        let groupID = try #require(subgroupProjection.resolvedGroups.first?.id)
        #expect(
            subgroupIndex.entries.compactMap { entry -> RepoExplorerRowID? in
                if case .activitySubgroup = entry { return entry.id }
                return nil
            } == [
                .activitySubgroup(groupID: groupID, bucket: .active),
                .activitySubgroup(groupID: groupID, bucket: .noActivity),
            ]
        )

        let mainActivityProjection = RepoExplorerProjection.project(
            base.replacing(groupingMode: .activity),
            paneRowFactsByPaneId: facts
        )
        let mainActivityIndex = RepoExplorerRowIndex(
            projection: mainActivityProjection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        #expect(
            mainActivityIndex.entries.allSatisfy { entry in
                if case .activitySubgroup = entry { return false }
                return true
            }
        )
    }

    @Test("sort field and direction reorder leaves only and keep unknown activity last")
    func sortMatrixReordersLeavesOnlyAndKeepsUnknownActivityLast() throws {
        let now = Date(timeIntervalSince1970: 1_788_804_000)
        let repoID = UUIDv7.generate()
        let worktree = worktree(repoId: repoID, name: "main")
        let olderPaneID = UUIDv7.generate()
        let newerPaneID = UUIDv7.generate()
        let unknownPaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let repository = repo(id: repoID, name: "repository", worktrees: [worktree])
        let base = RepoExplorerSnapshot(
            repos: [repository],
            repoEnrichmentByRepoId: [repoID: resolvedRemote(repoId: repoID, displayName: repository.name)],
            surface: .panes,
            groupingMode: .tab,
            referenceDate: now,
            calendar: organizationCalendar,
            query: "",
            paneLocationsByWorktreeId: [
                worktree.id: [
                    paneLocation(paneID: newerPaneID, tabID: tabID, paneIndex: 0),
                    paneLocation(paneID: unknownPaneID, tabID: tabID, paneIndex: 1),
                    paneLocation(paneID: olderPaneID, tabID: tabID, paneIndex: 2),
                ]
            ]
        )
        let facts = [
            olderPaneID: paneFacts(title: "Alpha", activityAt: now.addingTimeInterval(-3000)),
            newerPaneID: paneFacts(title: "Beta", activityAt: now.addingTimeInterval(-300)),
            unknownPaneID: paneFacts(title: "Gamma"),
        ]
        let cases: [(SidebarSortField, RepoExplorerSortOrder, [UUID])] = [
            (.name, .ascending, [olderPaneID, newerPaneID, unknownPaneID]),
            (.name, .descending, [unknownPaneID, newerPaneID, olderPaneID]),
            (.activity, .ascending, [olderPaneID, newerPaneID, unknownPaneID]),
            (.activity, .descending, [newerPaneID, olderPaneID, unknownPaneID]),
        ]

        var expectedGroupIDs: [String]?
        for (sortField, sortOrder, expectedPaneIDs) in cases {
            let projection = RepoExplorerProjection.project(
                base.replacing(sortField: sortField, sortOrder: sortOrder),
                paneRowFactsByPaneId: facts
            )
            let groupIDs = projection.resolvedGroups.map(\.id)
            if let expectedGroupIDs {
                #expect(groupIDs == expectedGroupIDs)
            } else {
                expectedGroupIDs = groupIDs
            }
            let groupID = try #require(groupIDs.first)
            #expect(projection.paneRowsByGroupId[groupID]?.map { $0.destination.paneId } == expectedPaneIDs)
        }
    }

    @Test("Repos worktree activity uses the newest eligible pane timestamp without focus fallback")
    func reposWorktreeActivityUsesNewestEligiblePaneTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_788_804_000)
        let repoID = UUIDv7.generate()
        let worktree = worktree(repoId: repoID, name: "main")
        let olderPaneID = UUIDv7.generate()
        let activePaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let repository = repo(id: repoID, name: "repository", worktrees: [worktree])
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: [repoID: resolvedRemote(repoId: repoID, displayName: repository.name)],
                surface: .repos,
                subgroupMode: .activity,
                referenceDate: now,
                calendar: organizationCalendar,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        paneLocation(paneID: olderPaneID, tabID: tabID, paneIndex: 0),
                        paneLocation(paneID: activePaneID, tabID: tabID, paneIndex: 1),
                    ]
                ]
            ),
            paneRowFactsByPaneId: [
                olderPaneID: paneFacts(
                    title: "Recently Focused",
                    activityAt: now.addingTimeInterval(-3000),
                    recencyReferenceDate: now
                ),
                activePaneID: paneFacts(
                    title: "Output Pane",
                    activityAt: now.addingTimeInterval(-30),
                    recencyReferenceDate: now.addingTimeInterval(-20_000)
                ),
            ]
        )

        let groupID = try #require(projection.resolvedGroups.first?.id)
        let row = try #require(projection.worktreeRowsByGroupId[groupID]?.first)
        #expect(row.activitySubgroup == .active)
    }

    private func paneLocation(
        paneID: UUID,
        tabID: UUID,
        tabIndex: Int = 0,
        paneIndex: Int = 0
    ) -> WorkspacePaneLocation {
        WorkspacePaneLocation(
            paneId: paneID,
            tabId: tabID,
            tabIndex: tabIndex,
            paneIndexInTab: paneIndex,
            isActiveInTab: paneIndex == 0
        )
    }

    private func paneFacts(
        title: String,
        activityAt: Date? = nil,
        isPinned: Bool = false,
        recencyReferenceDate: Date = Date(timeIntervalSince1970: 0)
    ) -> RepoExplorerPaneRowFacts {
        RepoExplorerPaneRowFacts(
            terminalTitle: title,
            activityAt: activityAt,
            isPinned: isPinned,
            latestMessageText: nil,
            recencyReferenceDate: recencyReferenceDate,
            recencyText: "Now",
            isActive: false
        )
    }

    private func paneIDs(
        in section: RepoExplorerSidebarSection,
        projection: RepoExplorerSidebarProjection
    ) -> [UUID] {
        section.resolvedGroups.flatMap { group in
            projection.paneRowsByGroupId[group.id, default: []].map { $0.destination.paneId }
        }
    }
}
