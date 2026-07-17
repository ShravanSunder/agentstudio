import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace arrangement selection transitions")
struct WorkspaceArrangementSelectionTransitionTests {
    @Test("main selection validates the exact active arrangement and main layout")
    func mainSelectionValidationIsStrict() {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let missingTabID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: missingTabID, selection: .selected(fixture.mainPaneIDs[0])),
            context: .missingTab
        )
        let missingActiveArrangement = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[0])),
            context: .missingActiveArrangement(tab: fixture.tabState)
        )
        let inactivePane = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.inactivePaneID)),
            context: fixture.activePaneContext
        )
        let drawerChild = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.drawerChildIDs[0])),
            context: fixture.activePaneContext
        )

        // Assert
        #expect(missingTab == .rejected(.missingTab(missingTabID)))
        #expect(missingActiveArrangement == .rejected(.missingActiveArrangement(fixture.tabID)))
        #expect(
            inactivePane
                == .rejected(
                    .paneNotInActiveMainLayout(
                        tabID: fixture.tabID,
                        arrangementID: fixture.activeArrangementID,
                        paneID: fixture.inactivePaneID
                    )
                )
        )
        #expect(
            drawerChild
                == .rejected(
                    .paneNotInActiveMainLayout(
                        tabID: fixture.tabID,
                        arrangementID: fixture.activeArrangementID,
                        paneID: fixture.drawerChildIDs[0]
                    )
                )
        )
    }

    @Test("main selection returns one exact keyed cursor replacement")
    func mainSelectionReturnsKeyedReplacement() {
        // Arrange
        let fixture = makeArrangementSelectionFixture()

        // Act
        let changed = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[1])),
            context: fixture.activePaneContext
        )
        let unchanged = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[0])),
            context: fixture.activePaneContext
        )

        // Assert
        guard case .changed(.activePane(let transition)) = changed else {
            Issue.record("expected changed active-pane transition")
            return
        }
        #expect(transition.expectedTabGraph == fixture.tabState)
        #expect(transition.expectedActiveArrangement == .selected(fixture.activeArrangementID))
        #expect(transition.expectedCursor == .present(.selected(fixture.mainPaneIDs[0])))
        #expect(
            transition.mutation
                == .replace(
                    arrangementID: fixture.activeArrangementID,
                    previous: fixture.mainPaneIDs[0],
                    replacement: fixture.mainPaneIDs[1]
                )
        )
        #expect(unchanged == .unchanged)
    }

    @Test("main selection uses missing and present-no-selection insertion plus selected removal shapes")
    func mainSelectionUsesStrictInsertionAndRemovalShapes() {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let missingContext = WorkspaceActivePaneSelectionPlanningContext.selectedActiveArrangement(
            tab: fixture.tabState,
            arrangementID: fixture.activeArrangementID,
            cursor: .missing
        )
        let noSelectionContext = WorkspaceActivePaneSelectionPlanningContext.selectedActiveArrangement(
            tab: fixture.tabState,
            arrangementID: fixture.activeArrangementID,
            cursor: .present(.noSelection)
        )

        // Act
        let missingInsertion = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[1])),
            context: missingContext
        )
        let noSelectionInsertion = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[1])),
            context: noSelectionContext
        )
        let removal = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .noSelection),
            context: fixture.activePaneContext
        )

        // Assert
        guard case .changed(.activePane(let insertedFromMissing)) = missingInsertion,
            case .changed(.activePane(let insertedFromNoSelection)) = noSelectionInsertion,
            case .changed(.activePane(let removed)) = removal
        else {
            Issue.record("expected insertion and removal transitions")
            return
        }
        #expect(
            insertedFromMissing.mutation
                == .insert(
                    arrangementID: fixture.activeArrangementID,
                    expected: .missing,
                    replacement: fixture.mainPaneIDs[1]
                )
        )
        #expect(
            insertedFromNoSelection.mutation
                == .insert(
                    arrangementID: fixture.activeArrangementID,
                    expected: .present(.noSelection),
                    replacement: fixture.mainPaneIDs[1]
                )
        )
        #expect(
            removed.mutation
                == .remove(
                    arrangementID: fixture.activeArrangementID,
                    previous: fixture.mainPaneIDs[0]
                )
        )
    }

    @Test("drawer selection validates exact drawer membership and returns one keyed replacement")
    func drawerSelectionIsStrictAndKeyed() {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let missingDrawerID = UUIDv7.generate()
        let missingChildID = UUIDv7.generate()

        // Act
        let missingDrawer = WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
            .init(tabID: fixture.tabID, drawerID: missingDrawerID, childPaneID: fixture.drawerChildIDs[0]),
            context: fixture.activeDrawerContext
        )
        let missingChild = WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
            .init(tabID: fixture.tabID, drawerID: fixture.drawerID, childPaneID: missingChildID),
            context: fixture.activeDrawerContext
        )
        let changed = WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
            .init(
                tabID: fixture.tabID,
                drawerID: fixture.drawerID,
                childPaneID: fixture.drawerChildIDs[1]
            ),
            context: fixture.activeDrawerContext
        )
        let unchanged = WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
            .init(
                tabID: fixture.tabID,
                drawerID: fixture.drawerID,
                childPaneID: fixture.drawerChildIDs[0]
            ),
            context: fixture.activeDrawerContext
        )

        // Assert
        #expect(
            missingDrawer
                == .rejected(
                    .missingDrawer(
                        tabID: fixture.tabID,
                        arrangementID: fixture.activeArrangementID,
                        drawerID: missingDrawerID
                    )
                )
        )
        #expect(
            missingChild
                == .rejected(
                    .drawerChildNotInActiveDrawer(
                        tabID: fixture.tabID,
                        arrangementID: fixture.activeArrangementID,
                        drawerID: fixture.drawerID,
                        paneID: missingChildID
                    )
                )
        )
        guard case .changed(.activeDrawerChild(let transition)) = changed else {
            Issue.record("expected changed drawer-child transition")
            return
        }
        #expect(transition.expectedTabGraph == fixture.tabState)
        #expect(transition.expectedActiveArrangement == .selected(fixture.activeArrangementID))
        #expect(transition.expectedCursor == .present(.selected(fixture.drawerChildIDs[0])))
        #expect(
            transition.mutation
                == .replace(
                    key: fixture.drawerCursorKey,
                    previous: fixture.drawerChildIDs[0],
                    replacement: fixture.drawerChildIDs[1]
                )
        )
        #expect(unchanged == .unchanged)
    }

    @Test("minimized main and drawer-child selections reject without unminimizing")
    func minimizedSelectionsReject() {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        var minimizedMainTab = fixture.tabState
        minimizedMainTab.arrangements[0].minimizedPaneIds.insert(fixture.mainPaneIDs[1])
        let minimizedMainContext = WorkspaceActivePaneSelectionPlanningContext.selectedActiveArrangement(
            tab: minimizedMainTab,
            arrangementID: fixture.activeArrangementID,
            cursor: .present(.selected(fixture.mainPaneIDs[0]))
        )
        var minimizedDrawerTab = fixture.tabState
        minimizedDrawerTab.arrangements[0].drawerViews[fixture.drawerID]?.minimizedPaneIds.insert(
            fixture.drawerChildIDs[1]
        )
        let minimizedDrawerContext =
            WorkspaceActiveDrawerChildSelectionPlanningContext.selectedActiveArrangement(
                tab: minimizedDrawerTab,
                arrangementID: fixture.activeArrangementID,
                cursor: .present(.selected(fixture.drawerChildIDs[0]))
            )

        // Act
        let mainDecision = WorkspaceSetActivePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[1])),
            context: minimizedMainContext
        )
        let drawerDecision = WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
            .init(
                tabID: fixture.tabID,
                drawerID: fixture.drawerID,
                childPaneID: fixture.drawerChildIDs[1]
            ),
            context: minimizedDrawerContext
        )

        // Assert
        #expect(
            mainDecision
                == .rejected(
                    .paneIsMinimizedInActiveMainLayout(
                        tabID: fixture.tabID,
                        arrangementID: fixture.activeArrangementID,
                        paneID: fixture.mainPaneIDs[1]
                    )
                )
        )
        #expect(
            drawerDecision
                == .rejected(
                    .drawerChildIsMinimizedInActiveDrawer(
                        tabID: fixture.tabID,
                        arrangementID: fixture.activeArrangementID,
                        drawerID: fixture.drawerID,
                        paneID: fixture.drawerChildIDs[1]
                    )
                )
        )
    }
}

struct ArrangementSelectionFixture {
    let tabID: UUID
    let activeArrangementID: UUID
    let inactiveArrangementID: UUID
    let drawerID: UUID
    let mainPaneIDs: [UUID]
    let inactivePaneID: UUID
    let drawerChildIDs: [UUID]
    let drawerCursorKey: ArrangementDrawerCursorKey
    let tabState: TabGraphState
    let activePaneContext: WorkspaceActivePaneSelectionPlanningContext
    let activeDrawerContext: WorkspaceActiveDrawerChildSelectionPlanningContext
}

func makeArrangementSelectionFixture() -> ArrangementSelectionFixture {
    let tabID = UUIDv7.generate()
    let activeArrangementID = UUIDv7.generate()
    let inactiveArrangementID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    let mainPaneIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let inactivePaneID = UUIDv7.generate()
    let drawerChildIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let drawerCursorKey = ArrangementDrawerCursorKey(
        arrangementId: activeArrangementID,
        drawerId: drawerID
    )
    let activeArrangement = PaneArrangementGraphState(
        id: activeArrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(
            panes: [
                .init(paneId: mainPaneIDs[0], ratio: 0.5),
                .init(paneId: mainPaneIDs[1], ratio: 0.5),
            ],
            dividerIds: [UUIDv7.generate()]
        ),
        minimizedPaneIds: [],
        showsMinimizedPanes: true,
        drawerViews: [
            drawerID: DrawerViewGraphState(
                layout: DrawerGridLayout(
                    topRow: Layout(
                        panes: [
                            .init(paneId: drawerChildIDs[0], ratio: 0.5),
                            .init(paneId: drawerChildIDs[1], ratio: 0.5),
                        ],
                        dividerIds: [UUIDv7.generate()]
                    )
                )
            )
        ]
    )
    let inactiveArrangement = PaneArrangementGraphState(
        id: inactiveArrangementID,
        name: "Other",
        isDefault: false,
        layout: Layout(paneId: inactivePaneID),
        minimizedPaneIds: [],
        showsMinimizedPanes: true,
        drawerViews: [:]
    )
    let tabState = TabGraphState(
        tabId: tabID,
        allPaneIds: mainPaneIDs + [inactivePaneID] + drawerChildIDs,
        arrangements: [activeArrangement, inactiveArrangement]
    )
    let activePaneContext = WorkspaceActivePaneSelectionPlanningContext.selectedActiveArrangement(
        tab: tabState,
        arrangementID: activeArrangementID,
        cursor: .present(.selected(mainPaneIDs[0]))
    )
    let activeDrawerContext =
        WorkspaceActiveDrawerChildSelectionPlanningContext.selectedActiveArrangement(
            tab: tabState,
            arrangementID: activeArrangementID,
            cursor: .present(.selected(drawerChildIDs[0]))
        )
    return ArrangementSelectionFixture(
        tabID: tabID,
        activeArrangementID: activeArrangementID,
        inactiveArrangementID: inactiveArrangementID,
        drawerID: drawerID,
        mainPaneIDs: mainPaneIDs,
        inactivePaneID: inactivePaneID,
        drawerChildIDs: drawerChildIDs,
        drawerCursorKey: drawerCursorKey,
        tabState: tabState,
        activePaneContext: activePaneContext,
        activeDrawerContext: activeDrawerContext
    )
}
