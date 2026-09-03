import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorer pane projection")
struct RepoExplorerPaneProjectionTests {
    @Test("pane and tab recency colors degrade through policy-owned time tiers")
    func recencyTierUsesPolicyThresholds() {
        let now = Date(timeIntervalSince1970: 100_000)

        #expect(
            RepoExplorerPaneRecencyTier.classify(referenceDate: now.addingTimeInterval(-60), now: now) == .strongBlue)
        #expect(
            RepoExplorerPaneRecencyTier.classify(referenceDate: now.addingTimeInterval(-(10 * 60)), now: now)
                == .mediumBlue
        )
        #expect(
            RepoExplorerPaneRecencyTier.classify(referenceDate: now.addingTimeInterval(-(60 * 60)), now: now)
                == .mutedBlue
        )
        #expect(
            RepoExplorerPaneRecencyTier.classify(referenceDate: now.addingTimeInterval(-(12 * 60 * 60)), now: now)
                == .faintBlue
        )
        #expect(
            RepoExplorerPaneRecencyTier.classify(referenceDate: now.addingTimeInterval(-(24 * 60 * 60)), now: now)
                == .grey
        )
    }

    @Test("pane note wins over terminal output and empty panes omit L2")
    func paneSecondaryLineUsesNoteThenTerminalOutputThenNothing() {
        let referenceDate = Date(timeIntervalSince1970: 10)
        let notedPane = RepoExplorerPaneRowFacts(
            terminalTitle: "zsh",
            noteText: "Waiting on review",
            latestMessageText: "Tests passed",
            recencyReferenceDate: referenceDate,
            recencyText: "Now",
            isActive: false
        )
        let activePane = RepoExplorerPaneRowFacts(
            terminalTitle: "zsh",
            latestMessageText: "Tests passed",
            recencyReferenceDate: referenceDate,
            recencyText: "Now",
            isActive: false
        )
        let quietPane = RepoExplorerPaneRowFacts(
            terminalTitle: "zsh",
            latestMessageText: nil,
            recencyReferenceDate: referenceDate,
            recencyText: "Now",
            isActive: false
        )

        #expect(notedPane.secondaryLine == .note("Waiting on review"))
        #expect(activePane.secondaryLine == .terminalOutput("Tests passed"))
        #expect(quietPane.secondaryLine == nil)

        let drawerPane = RepoExplorerPaneRowFacts(
            terminalTitle: "Drawer",
            latestMessageText: nil,
            recencyReferenceDate: referenceDate,
            recencyText: "Now",
            isActive: false,
            isDrawerPane: true
        )
        #expect(drawerPane.sidebarTerminalTitle == "zsh")
    }

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
                    latestMessageText: "No activity yet",
                    recencyReferenceDate: Date(timeIntervalSince1970: 10),
                    recencyText: "2m",
                    isActive: false
                ),
                newerPaneId: .init(
                    terminalTitle: "tests running",
                    latestMessageText: "Tests passed",
                    recencyReferenceDate: Date(timeIntervalSince1970: 20),
                    recencyText: "Now",
                    isActive: true,
                    isDrawerPane: true
                ),
            ]
        )

        let group = try #require(projection.resolvedGroups.first)
        let rows = try #require(projection.paneRowsByGroupId[group.id])
        #expect(rows.map(\.destination.paneId) == [newerPaneId, olderPaneId])
        #expect(rows[0].primaryText == "Pane 2 · tests running")
        #expect(rows[0].secondaryText == "Tests passed")
        #expect(rows[0].recencyText == "Now")
        #expect(rows[0].isActive)
        #expect(rows[0].isDrawerPane)
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
                    latestMessageText: "No activity yet",
                    recencyReferenceDate: Date(timeIntervalSince1970: 20),
                    recencyText: "Now",
                    isActive: true
                ),
                previouslyFocusedPaneId: .init(
                    terminalTitle: "old pane",
                    latestMessageText: "No activity yet",
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

    @Test("By Tab uses display titles, pane counts, tab order, and exact pane rows")
    func byTabProjectsPaneRowsUnderDisplayTitleHeaders() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let firstTabId = UUIDv7.generate()
        let secondTabId = UUIDv7.generate()
        let firstPaneId = UUIDv7.generate()
        let secondPaneId = UUIDv7.generate()
        let thirdPaneId = UUIDv7.generate()
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
                        .init(
                            paneId: thirdPaneId,
                            tabId: firstTabId,
                            tabIndex: 0,
                            paneIndexInTab: 1,
                            isActiveInTab: false
                        ),
                    ]
                ]
            ),
            paneRowFactsByPaneId: [
                firstPaneId: .init(
                    terminalTitle: "first terminal",
                    latestMessageText: "First message",
                    recencyReferenceDate: Date(timeIntervalSince1970: 10),
                    recencyText: "Now",
                    isActive: true
                ),
                secondPaneId: .init(
                    terminalTitle: "second terminal",
                    latestMessageText: "Second message",
                    recencyReferenceDate: Date(timeIntervalSince1970: 20),
                    recencyText: "Now",
                    isActive: false
                ),
                thirdPaneId: .init(
                    terminalTitle: "third terminal",
                    latestMessageText: "Third message",
                    recencyReferenceDate: Date(timeIntervalSince1970: 30),
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
        #expect(projection.resolvedGroups.map(\.organizationName) == ["2 panes", "1 pane"])
        #expect(projection.worktreeRowsByGroupId.isEmpty)
        let firstTabRows = try #require(projection.paneRowsByGroupId[projection.resolvedGroups[0].id])
        #expect(firstTabRows.map(\.destination.paneId) == [firstPaneId, thirdPaneId])
        #expect(firstTabRows.map(\.primaryText) == ["Pane 1 · first terminal", "Pane 2 · third terminal"])
        #expect(firstTabRows.map(\.secondaryText) == ["First message", "Third message"])
    }

    @Test("By Tab membership includes associated and unassociated panes in their canonical tabs")
    func byTabIncludesMixedAndAllUnassociatedTabs() throws {
        let fixture = makeMixedAndUnassociatedTabFixture()
        let projection = fixture.projection
        let repoId = fixture.repoId
        let mixedTabId = fixture.mixedTabId
        let unassociatedTabId = fixture.unassociatedTabId
        let associatedPaneId = fixture.associatedPaneId
        let mixedUnassociatedPaneId = fixture.mixedUnassociatedPaneId
        let unassociatedOnlyPaneId = fixture.unassociatedOnlyPaneId

        #expect(projection.resolvedGroups.map(\.repoTitle) == ["Mixed", "Unassociated"])
        #expect(projection.resolvedGroups.map(\.organizationName) == ["2 panes", "1 pane"])
        let mixedRows = try #require(projection.paneRowsByGroupId["tab:\(mixedTabId.uuidString)"])
        #expect(mixedRows.map(\.destination.paneId) == [associatedPaneId, mixedUnassociatedPaneId])
        let unassociatedRows = try #require(
            projection.paneRowsByGroupId["tab:\(unassociatedTabId.uuidString)"]
        )
        #expect(unassociatedRows.map(\.destination.paneId) == [unassociatedOnlyPaneId])

        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        let paneEntries = rowIndex.entries.compactMap { entry -> (String, UUID)? in
            guard case .resolvedPaneRow(let groupId, let identity, _) = entry else { return nil }
            return (groupId, identity.paneId)
        }
        #expect(
            paneEntries.map(\.1)
                == [associatedPaneId, mixedUnassociatedPaneId, unassociatedOnlyPaneId]
        )
        let resolvedRows = rowIndex.entries.compactMap { entry -> RepoExplorerResolvedPaneContext? in
            guard case .resolvedPaneRow(let groupId, let identity, let rowId) = entry else { return nil }
            guard case .tabPane(let rowGroupId, let paneId) = rowId else {
                Issue.record("By Tab rows require tab-owned identity")
                return nil
            }
            #expect(rowGroupId == groupId)
            #expect(paneId == identity.paneId)
            return rowIndex.resolvePane(
                groupId: groupId,
                repoId: identity.repoId,
                paneId: identity.paneId,
                rowId: rowId
            )
        }
        #expect(resolvedRows.map(\.destination.paneId) == paneEntries.map(\.1))
        #expect(resolvedRows.map(\.row.repoId) == [repoId, nil, nil])
        #expect(resolvedRows.map(\.row.isActive) == [true, false, true])

        let collapsed = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: ["tab:\(mixedTabId.uuidString)"],
            isFiltering: false
        )
        #expect(
            !collapsed.entries.contains { entry in
                guard case .resolvedPaneRow(let groupId, _, _) = entry else { return false }
                return groupId == "tab:\(mixedTabId.uuidString)"
            }
        )
    }

    @Test("By Tab repository association changes enrichment without changing membership identity")
    func byTabAssociationTransitionPreservesMembershipIdentity() throws {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let tabId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let location = WorkspacePaneLocation(
            paneId: paneId,
            tabId: tabId,
            tabIndex: 0,
            paneIndexInTab: 0,
            isActiveInTab: true
        )
        let repository = makeRepo(id: repoId, worktrees: [worktree])
        let associated = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [worktree.id: [location]]
            ),
            branchNameByWorktreeId: [worktree.id: "main"],
            branchStatusByWorktreeId: [worktree.id: .unknown]
        )
        let unassociated = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repository],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                unassociatedPaneLocations: [location]
            )
        )

        #expect(associated.resolvedGroups.map(\.id) == unassociated.resolvedGroups.map(\.id))
        #expect(associated.resolvedGroups.map(\.organizationName) == ["1 pane"])
        #expect(unassociated.resolvedGroups.map(\.organizationName) == ["1 pane"])
        let associatedIndex = RepoExplorerRowIndex(
            projection: associated,
            collapsedGroupIds: [],
            isFiltering: false
        )
        let unassociatedIndex = RepoExplorerRowIndex(
            projection: unassociated,
            collapsedGroupIds: [],
            isFiltering: false
        )
        let associatedRowID = try #require(
            associatedIndex.entries.compactMap { entry -> RepoExplorerRowID? in
                guard case .resolvedPaneRow(_, _, let rowID) = entry else { return nil }
                return rowID
            }.first
        )
        let unassociatedRowID = try #require(
            unassociatedIndex.entries.compactMap { entry -> RepoExplorerRowID? in
                guard case .resolvedPaneRow(_, _, let rowID) = entry else { return nil }
                return rowID
            }.first
        )
        #expect(associatedRowID == unassociatedRowID)
        #expect(associatedRowID == .tabPane(groupID: "tab:\(tabId.uuidString)", paneID: paneId))
        let associatedRow = try #require(associated.paneRowsByGroupId["tab:\(tabId.uuidString)"]?.first)
        let unassociatedRow = try #require(unassociated.paneRowsByGroupId["tab:\(tabId.uuidString)"]?.first)
        #expect(associatedRow.repoId == repoId)
        #expect(associatedRow.worktreeId == worktree.id)
        #expect(associatedRow.branchContextText == "agent-studio · main")
        #expect(unassociatedRow.repoId == nil)
        #expect(unassociatedRow.worktreeId == nil)
        #expect(unassociatedRow.branchContextText == nil)
        #expect(unassociatedRow.branchStatus == nil)
    }

    @Test("empty states distinguish no repositories, no panes, and no tabs")
    func emptyStatesMatchGroupingMode() {
        let emptyRepoProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(repos: [], repoEnrichmentByRepoId: [:], groupingMode: .repo, query: "")
        )
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let repo = makeRepo(id: repoId, worktrees: [worktree])
        let enrichment = [repoId: resolvedRemote(repoId: repoId)]
        let emptyPaneProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .pane,
                query: ""
            )
        )
        let emptyTabProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: enrichment,
                groupingMode: .tab,
                query: ""
            )
        )

        #expect(emptyRepoProjection.emptyState == .noRepositories)
        #expect(emptyPaneProjection.emptyState == .noPanes)
        #expect(emptyTabProjection.emptyState == .noTabs)
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
        #expect(ungroupedSection.title == "No Repositories")
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

    private func makeMixedAndUnassociatedTabFixture() -> ByTabMembershipFixture {
        let repoId = UUIDv7.generate()
        let worktree = makeWorktree(repoId: repoId)
        let mixedTabId = UUIDv7.generate()
        let unassociatedTabId = UUIDv7.generate()
        let associatedPaneId = UUIDv7.generate()
        let mixedUnassociatedPaneId = UUIDv7.generate()
        let unassociatedOnlyPaneId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [makeRepo(id: repoId, worktrees: [worktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .tab,
                query: "",
                paneLocationsByWorktreeId: [
                    worktree.id: [
                        WorkspacePaneLocation(
                            paneId: associatedPaneId,
                            tabId: mixedTabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ],
                unassociatedPaneLocations: [
                    WorkspacePaneLocation(
                        paneId: mixedUnassociatedPaneId,
                        tabId: mixedTabId,
                        tabIndex: 0,
                        paneIndexInTab: 1,
                        isActiveInTab: false
                    ),
                    WorkspacePaneLocation(
                        paneId: unassociatedOnlyPaneId,
                        tabId: unassociatedTabId,
                        tabIndex: 1,
                        paneIndexInTab: 0,
                        isActiveInTab: true
                    ),
                ]
            ),
            paneRowFactsByPaneId: [
                associatedPaneId: paneFacts(
                    title: "associated", activity: "Associated activity", time: 30, isActive: true),
                mixedUnassociatedPaneId: paneFacts(
                    title: "mixed unassociated", activity: "Mixed activity", time: 20, recency: "1m"),
                unassociatedOnlyPaneId: paneFacts(
                    title: "unassociated only", activity: "Unassociated activity", time: 10, recency: "2m",
                    isActive: true),
            ],
            tabGroupFactsByTabId: [
                mixedTabId: .init(displayTitle: "Mixed"),
                unassociatedTabId: .init(displayTitle: "Unassociated"),
            ]
        )
        return ByTabMembershipFixture(
            projection: projection,
            repoId: repoId,
            mixedTabId: mixedTabId,
            unassociatedTabId: unassociatedTabId,
            associatedPaneId: associatedPaneId,
            mixedUnassociatedPaneId: mixedUnassociatedPaneId,
            unassociatedOnlyPaneId: unassociatedOnlyPaneId
        )
    }

    private func paneFacts(
        title: String,
        activity: String,
        time: TimeInterval,
        recency: String = "Now",
        isActive: Bool = false
    ) -> RepoExplorerPaneRowFacts {
        RepoExplorerPaneRowFacts(
            terminalTitle: title,
            latestMessageText: activity,
            recencyReferenceDate: Date(timeIntervalSince1970: time),
            recencyText: recency,
            isActive: isActive
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

private struct ByTabMembershipFixture {
    let projection: RepoExplorerSidebarProjection
    let repoId: UUID
    let mixedTabId: UUID
    let unassociatedTabId: UUID
    let associatedPaneId: UUID
    let mixedUnassociatedPaneId: UUID
    let unassociatedOnlyPaneId: UUID
}
