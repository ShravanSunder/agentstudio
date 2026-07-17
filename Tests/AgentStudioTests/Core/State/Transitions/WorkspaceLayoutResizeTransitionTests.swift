import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace layout resize transitions")
struct WorkspaceLayoutResizeTransitionTests {
    @Test("main split produces one target-keyed replacement")
    func mainSplitProducesTargetReplacement() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let splitID = fixture.tabState.arrangements[1].layout.dividerIds[0]
        let checkpoint = WorkspaceLayoutResizeCheckpoint.mainSplit(
            tabID: fixture.tabState.tabId,
            arrangementID: fixture.customArrangementID,
            splitID: splitID,
            ratio: 0.4
        )

        // Act
        let decision = WorkspaceLayoutResizeTransitionPlanner.plan(
            checkpoint,
            context: .selectedActiveArrangement(
                tab: fixture.tabState,
                arrangementID: fixture.customArrangementID
            )
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed resize transition")
            return
        }
        #expect(transition.previousTabGraph == fixture.tabState)
        #expect(transition.replacementTabGraph.arrangements[1].layout.ratioForSplit(splitID) == 0.4)
        #expect(transition.replacementTabGraph.arrangements[0] == fixture.tabState.arrangements[0])
    }

    @Test("invalid identity, freshness, ratio, and split shapes reject explicitly")
    func invalidShapesRejectExplicitly() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let missingTabID = UUIDv7.generate()
        let missingArrangementID = UUIDv7.generate()
        let missingSplitID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainSplit(
                tabID: missingTabID,
                arrangementID: fixture.customArrangementID,
                splitID: missingSplitID,
                ratio: 0.5
            ),
            context: .missingTab
        )
        let missingArrangement = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: missingArrangementID,
                splitID: missingSplitID,
                ratio: 0.5
            ),
            context: .selectedActiveArrangement(
                tab: fixture.tabState,
                arrangementID: fixture.customArrangementID
            )
        )
        let invalidRatio = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: missingSplitID,
                ratio: .infinity
            ),
            context: .selectedActiveArrangement(
                tab: fixture.tabState,
                arrangementID: fixture.customArrangementID
            )
        )
        let missingSplit = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: missingSplitID,
                ratio: 0.5
            ),
            context: .selectedActiveArrangement(
                tab: fixture.tabState,
                arrangementID: fixture.customArrangementID
            )
        )

        // Assert
        #expect(missingTab == .rejected(.missingTab(missingTabID)))
        #expect(
            missingArrangement
                == .rejected(
                    .activeArrangementMismatch(
                        tabID: fixture.tabState.tabId,
                        requested: missingArrangementID,
                        active: fixture.customArrangementID
                    )
                )
        )
        #expect(invalidRatio == .rejected(.invalidRatio(.infinity)))
        #expect(
            missingSplit
                == .rejected(
                    .missingMainSplit(
                        tabID: fixture.tabState.tabId,
                        arrangementID: fixture.customArrangementID,
                        splitID: missingSplitID
                    )
                )
        )
    }

    @Test("visible-pair and drawer checkpoints preserve their exact layout lane")
    func visiblePairAndDrawerCheckpointsPreserveExactLane() throws {
        // Arrange
        let fixture = makeLayoutResizeFixture()
        let context = WorkspaceLayoutResizePlanningContext.selectedActiveArrangement(
            tab: fixture.tab,
            arrangementID: fixture.arrangementID
        )

        // Act
        let mainPair = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainVisiblePair(
                tabID: fixture.tab.tabId,
                arrangementID: fixture.arrangementID,
                leftPaneID: fixture.mainPaneIDs[0],
                rightPaneID: fixture.mainPaneIDs[2],
                ratio: 0.4
            ),
            context: context
        )
        let drawerSplit = WorkspaceLayoutResizeTransitionPlanner.plan(
            .drawerSplit(
                tabID: fixture.tab.tabId,
                arrangementID: fixture.arrangementID,
                drawerID: fixture.drawerID,
                splitID: fixture.drawerSplitID,
                ratio: 0.4
            ),
            context: context
        )
        let drawerPair = WorkspaceLayoutResizeTransitionPlanner.plan(
            .drawerVisiblePair(
                tabID: fixture.tab.tabId,
                arrangementID: fixture.arrangementID,
                drawerID: fixture.drawerID,
                leftPaneID: fixture.drawerTopPaneIDs[0],
                rightPaneID: fixture.drawerTopPaneIDs[2],
                ratio: 0.4
            ),
            context: context
        )

        // Assert
        guard
            case .changed(let mainPairTransition) = mainPair,
            case .changed(let drawerSplitTransition) = drawerSplit,
            case .changed(let drawerPairTransition) = drawerPair
        else {
            Issue.record("expected all three resize checkpoint variants to change")
            return
        }
        #expect(
            abs(
                try #require(
                    mainPairTransition.replacementTabGraph.arrangements[0].layout.ratioForPanePair(
                        leftPaneId: fixture.mainPaneIDs[0],
                        rightPaneId: fixture.mainPaneIDs[2]
                    )
                ) - 0.4
            ) < 0.000001
        )
        #expect(
            abs(
                try #require(
                    drawerSplitTransition.replacementTabGraph.arrangements[0].drawerViews[fixture.drawerID]?
                        .layout.ratioForSplit(fixture.drawerSplitID)
                ) - 0.4
            ) < 0.000001
        )
        #expect(
            abs(
                try #require(
                    drawerPairTransition.replacementTabGraph.arrangements[0].drawerViews[fixture.drawerID]?
                        .layout.topRow.ratioForPanePair(
                            leftPaneId: fixture.drawerTopPaneIDs[0],
                            rightPaneId: fixture.drawerTopPaneIDs[2]
                        )
                ) - 0.4
            ) < 0.000001
        )
    }

    @Test("drawer row and collapsed-run validation rejects malformed pairs")
    func drawerPairValidationRejectsMalformedPairs() {
        // Arrange
        let fixture = makeLayoutResizeFixture()
        let context = WorkspaceLayoutResizePlanningContext.selectedActiveArrangement(
            tab: fixture.tab,
            arrangementID: fixture.arrangementID
        )

        // Act
        let crossesRows = WorkspaceLayoutResizeTransitionPlanner.plan(
            .drawerVisiblePair(
                tabID: fixture.tab.tabId,
                arrangementID: fixture.arrangementID,
                drawerID: fixture.drawerID,
                leftPaneID: fixture.drawerTopPaneIDs[0],
                rightPaneID: fixture.drawerBottomPaneID,
                ratio: 0.5
            ),
            context: context
        )
        let invalidCollapsedRun = WorkspaceLayoutResizeTransitionPlanner.plan(
            .drawerVisiblePair(
                tabID: fixture.tab.tabId,
                arrangementID: fixture.arrangementID,
                drawerID: fixture.drawerID,
                leftPaneID: fixture.drawerTopPaneIDs[0],
                rightPaneID: fixture.drawerTopPaneIDs[1],
                ratio: 0.5
            ),
            context: context
        )
        let missingMemberID = UUIDv7.generate()
        let missingMember = WorkspaceLayoutResizeTransitionPlanner.plan(
            .drawerVisiblePair(
                tabID: fixture.tab.tabId,
                arrangementID: fixture.arrangementID,
                drawerID: fixture.drawerID,
                leftPaneID: fixture.drawerTopPaneIDs[0],
                rightPaneID: missingMemberID,
                ratio: 0.5
            ),
            context: context
        )

        // Assert
        #expect(
            crossesRows
                == .rejected(
                    .drawerVisiblePairCrossesRows(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        drawerID: fixture.drawerID,
                        leftPaneID: fixture.drawerTopPaneIDs[0],
                        rightPaneID: fixture.drawerBottomPaneID
                    )
                )
        )
        #expect(
            invalidCollapsedRun
                == .rejected(
                    .invalidDrawerVisiblePair(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        drawerID: fixture.drawerID,
                        leftPaneID: fixture.drawerTopPaneIDs[0],
                        rightPaneID: fixture.drawerTopPaneIDs[1]
                    )
                )
        )
        #expect(
            missingMember
                == .rejected(
                    .invalidDrawerVisiblePair(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        drawerID: fixture.drawerID,
                        leftPaneID: fixture.drawerTopPaneIDs[0],
                        rightPaneID: missingMemberID
                    )
                )
        )
    }

    @Test("ratio boundaries are inclusive and exact current ratio is unchanged")
    func ratioBoundariesAndUnchangedAreExplicit() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let splitID = fixture.tabState.arrangements[1].layout.dividerIds[0]
        let context = WorkspaceLayoutResizePlanningContext.selectedActiveArrangement(
            tab: fixture.tabState,
            arrangementID: fixture.customArrangementID
        )
        func checkpoint(_ ratio: Double) -> WorkspaceLayoutResizeCheckpoint {
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: splitID,
                ratio: ratio
            )
        }

        // Act
        let lowerBoundary = WorkspaceLayoutResizeTransitionPlanner.plan(checkpoint(0.1), context: context)
        let upperBoundary = WorkspaceLayoutResizeTransitionPlanner.plan(checkpoint(0.9), context: context)
        let belowBoundary = WorkspaceLayoutResizeTransitionPlanner.plan(checkpoint(0.099), context: context)
        let aboveBoundary = WorkspaceLayoutResizeTransitionPlanner.plan(checkpoint(0.901), context: context)
        let unchanged = WorkspaceLayoutResizeTransitionPlanner.plan(checkpoint(0.7), context: context)

        // Assert
        guard case .changed = lowerBoundary, case .changed = upperBoundary else {
            Issue.record("expected inclusive ratio boundaries")
            return
        }
        #expect(belowBoundary == .rejected(.invalidRatio(0.099)))
        #expect(aboveBoundary == .rejected(.invalidRatio(0.901)))
        #expect(unchanged == .unchanged)
    }
}

private struct LayoutResizeFixture {
    let tab: TabGraphState
    let arrangementID: UUID
    let mainPaneIDs: [UUID]
    let drawerID: UUID
    let drawerTopPaneIDs: [UUID]
    let drawerBottomPaneID: UUID
    let drawerSplitID: UUID
}

private func makeLayoutResizeFixture() -> LayoutResizeFixture {
    let mainPaneIDs = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
    let drawerTopPaneIDs = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
    let drawerBottomPaneID = UUIDv7.generate()
    let drawerSplitIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let drawerID = UUIDv7.generate()
    let arrangementID = UUIDv7.generate()
    let drawer = DrawerViewGraphState(
        layout: DrawerGridLayout(
            topRow: Layout(
                panes: zip(drawerTopPaneIDs, [0.5, 0.2, 0.3]).map {
                    .init(paneId: $0.0, ratio: $0.1)
                },
                dividerIds: drawerSplitIDs
            ),
            bottomRow: Layout(paneId: drawerBottomPaneID)
        ),
        minimizedPaneIds: [drawerTopPaneIDs[1]]
    )
    let arrangement = PaneArrangementGraphState(
        id: arrangementID,
        name: "Layout",
        isDefault: false,
        layout: Layout(
            panes: zip(mainPaneIDs, [0.5, 0.2, 0.3]).map {
                .init(paneId: $0.0, ratio: $0.1)
            },
            dividerIds: [UUIDv7.generate(), UUIDv7.generate()]
        ),
        minimizedPaneIds: [mainPaneIDs[1]],
        showsMinimizedPanes: false,
        drawerViews: [drawerID: drawer]
    )
    return LayoutResizeFixture(
        tab: TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: mainPaneIDs + drawerTopPaneIDs + [drawerBottomPaneID],
            arrangements: [arrangement]
        ),
        arrangementID: arrangementID,
        mainPaneIDs: mainPaneIDs,
        drawerID: drawerID,
        drawerTopPaneIDs: drawerTopPaneIDs,
        drawerBottomPaneID: drawerBottomPaneID,
        drawerSplitID: drawerSplitIDs[0]
    )
}
