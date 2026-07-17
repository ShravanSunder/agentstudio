import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace keyboard resize checkpoint planner")
struct WorkspaceKeyboardResizeCheckpointPlannerTests {
    @Test("horizontal directions emit the exact adjacent split checkpoint")
    func horizontalDirectionsEmitAdjacentSplitCheckpoint() {
        // Arrange
        let fixture = makeKeyboardResizeFixture()

        // Act
        let increase = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[0], direction: .right, amount: 10),
            context: fixture.context
        )
        let decrease = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[1], direction: .left, amount: 10),
            context: fixture.context
        )

        // Assert
        let splitID = fixture.tab.arrangements[0].layout.dividerIds[0]
        let expectedIncrease = WorkspaceLayoutResizeCheckpoint.mainSplit(
            tabID: fixture.tab.tabId,
            arrangementID: fixture.arrangementID,
            splitID: splitID,
            ratio: 0.7 + 0.05
        )
        let expectedDecrease = WorkspaceLayoutResizeCheckpoint.mainSplit(
            tabID: fixture.tab.tabId,
            arrangementID: fixture.arrangementID,
            splitID: splitID,
            ratio: 0.7 - 0.05
        )
        #expect(increase == .changed(expectedIncrease))
        #expect(decrease == .changed(expectedDecrease))
    }

    @Test("vertical directions reject when the horizontal layout has no pair")
    func verticalDirectionsRejectMissingPair() {
        // Arrange
        let fixture = makeKeyboardResizeFixture()

        // Act
        let up = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[0], direction: .up, amount: 10),
            context: fixture.context
        )
        let down = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[0], direction: .down, amount: 10),
            context: fixture.context
        )

        // Assert
        #expect(
            up
                == .rejected(
                    .missingVisiblePair(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        paneID: fixture.paneIDs[0],
                        direction: .up
                    )
                )
        )
        #expect(
            down
                == .rejected(
                    .missingVisiblePair(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        paneID: fixture.paneIDs[0],
                        direction: .down
                    )
                )
        )
    }

    @Test("a minimized run resolves to the surrounding visible panes")
    func minimizedRunResolvesSurroundingPair() {
        // Arrange
        let fixture = makeKeyboardResizeFixture(paneRatios: [0.4, 0.2, 0.4], minimizedIndexes: [1])

        // Act
        let decision = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[0], direction: .right, amount: 10),
            context: fixture.context
        )

        // Assert
        #expect(
            decision
                == .changed(
                    .mainVisiblePair(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        leftPaneID: fixture.paneIDs[0],
                        rightPaneID: fixture.paneIDs[2],
                        ratio: 0.55
                    )
                )
        )
    }

    @Test("missing graph and arrangement witnesses reject explicitly")
    func missingGraphAndArrangementWitnessesReject() {
        // Arrange
        let fixture = makeKeyboardResizeFixture()
        let missingArrangementID = UUIDv7.generate()
        let request = WorkspaceKeyboardResizeRequest(
            tabID: fixture.tab.tabId,
            paneID: fixture.paneIDs[0],
            direction: .right,
            amount: 10
        )

        // Act
        let missingTab = WorkspaceKeyboardResizeCheckpointPlanner.plan(request, context: .missingTab)
        let missingActiveArrangement = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            request,
            context: .present(tab: fixture.tab, activeArrangement: .missing, zoom: .notZoomed)
        )
        let missingArrangement = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            request,
            context: .present(
                tab: fixture.tab,
                activeArrangement: .selected(missingArrangementID),
                zoom: .notZoomed
            )
        )

        // Assert
        #expect(missingTab == .rejected(.missingTab(fixture.tab.tabId)))
        #expect(missingActiveArrangement == .rejected(.missingActiveArrangement(fixture.tab.tabId)))
        #expect(
            missingArrangement
                == .rejected(
                    .missingArrangement(
                        tabID: fixture.tab.tabId,
                        arrangementID: missingArrangementID
                    )
                )
        )
    }

    @Test("missing pane, pair, and current ratio reject explicitly")
    func missingPanePairAndRatioReject() {
        // Arrange
        let fixture = makeKeyboardResizeFixture()
        let missingPaneID = UUIDv7.generate()
        let invalidRatioFixture = makeKeyboardResizeFixture(paneRatios: [.infinity, 1])

        // Act
        let missingPane = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: missingPaneID, direction: .right, amount: 10),
            context: fixture.context
        )
        let missingPair = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[1], direction: .right, amount: 10),
            context: fixture.context
        )
        let missingRatio = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(
                tabID: invalidRatioFixture.tab.tabId,
                paneID: invalidRatioFixture.paneIDs[0],
                direction: .right,
                amount: 10
            ),
            context: invalidRatioFixture.context
        )

        // Assert
        #expect(
            missingPane
                == .rejected(
                    .missingPane(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        paneID: missingPaneID
                    )
                )
        )
        #expect(
            missingPair
                == .rejected(
                    .missingVisiblePair(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.arrangementID,
                        paneID: fixture.paneIDs[1],
                        direction: .right
                    )
                )
        )
        #expect(
            missingRatio
                == .rejected(
                    .missingCurrentRatio(
                        tabID: invalidRatioFixture.tab.tabId,
                        arrangementID: invalidRatioFixture.arrangementID,
                        leftPaneID: invalidRatioFixture.paneIDs[0],
                        rightPaneID: invalidRatioFixture.paneIDs[1]
                    )
                )
        )
    }

    @Test("zoom, zero amount, and clamped boundary do not emit mutations")
    func zoomZeroAndClampDoNotEmitMutations() {
        // Arrange
        let fixture = makeKeyboardResizeFixture()
        let zoomedPaneID = fixture.paneIDs[0]
        let boundaryFixture = makeKeyboardResizeFixture(paneRatios: [0.9, 0.1])

        // Act
        let zoomed = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[0], direction: .right, amount: 10),
            context: .present(
                tab: fixture.tab,
                activeArrangement: .selected(fixture.arrangementID),
                zoom: .zoomed(zoomedPaneID)
            )
        )
        let zero = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(tabID: fixture.tab.tabId, paneID: fixture.paneIDs[0], direction: .right, amount: 0),
            context: fixture.context
        )
        let clamped = WorkspaceKeyboardResizeCheckpointPlanner.plan(
            .init(
                tabID: boundaryFixture.tab.tabId,
                paneID: boundaryFixture.paneIDs[0],
                direction: .right,
                amount: 10
            ),
            context: boundaryFixture.context
        )

        // Assert
        #expect(zoomed == .rejected(.zoomed(tabID: fixture.tab.tabId, paneID: zoomedPaneID)))
        #expect(zero == .unchanged)
        #expect(clamped == .unchanged)
    }
}

private struct WorkspaceKeyboardResizeFixture {
    let tab: TabGraphState
    let arrangementID: UUID
    let paneIDs: [UUID]

    var context: WorkspaceKeyboardResizePlanningContext {
        .present(
            tab: tab,
            activeArrangement: .selected(arrangementID),
            zoom: .notZoomed
        )
    }
}

private func makeKeyboardResizeFixture(
    paneRatios: [Double] = [0.7, 0.3],
    minimizedIndexes: Set<Int> = []
) -> WorkspaceKeyboardResizeFixture {
    let paneIDs = paneRatios.map { _ in UUIDv7.generate() }
    let arrangementID = UUIDv7.generate()
    let layout = Layout(
        panes: zip(paneIDs, paneRatios).map { Layout.PaneEntry(paneId: $0.0, ratio: $0.1) },
        dividerIds: (1..<paneIDs.count).map { _ in UUIDv7.generate() }
    )
    let arrangement = PaneArrangementGraphState(
        id: arrangementID,
        name: "Keyboard",
        isDefault: true,
        layout: layout,
        minimizedPaneIds: Set(minimizedIndexes.map { paneIDs[$0] }),
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
    return WorkspaceKeyboardResizeFixture(
        tab: TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: paneIDs,
            arrangements: [arrangement]
        ),
        arrangementID: arrangementID,
        paneIDs: paneIDs
    )
}
