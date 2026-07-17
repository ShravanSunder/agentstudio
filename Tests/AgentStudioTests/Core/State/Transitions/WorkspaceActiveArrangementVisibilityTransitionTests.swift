import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace active arrangement visibility transitions")
struct WorkspaceVisibilityTransitionTests {
    @Test("switch repairs the target pane cursor and clears transient zoom")
    func switchRepairsTargetCursorAndClearsZoom() {
        // Arrange
        let fixture = makeVisibilityFixture()
        let context = WorkspaceSwitchArrangementPlanningContext(
            tab: .present(fixture.tabState),
            activeArrangement: fixture.activeArrangement,
            targetPaneCursor: .present(.selected(fixture.paneIDs[2])),
            zoom: fixture.zoom
        )

        // Act
        let decision = WorkspaceSwitchArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabID, arrangementID: fixture.customArrangementID),
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed switch transition")
            return
        }
        #expect(
            transition.activeArrangement
                == .replace(
                    tabID: fixture.tabID,
                    previous: fixture.defaultArrangementID,
                    replacement: fixture.customArrangementID
                )
        )
        #expect(
            transition.activePane
                == .replace(
                    arrangementID: fixture.customArrangementID,
                    previous: fixture.paneIDs[2],
                    replacement: fixture.paneIDs[1]
                )
        )
        #expect(transition.zoom == .clear(tabID: fixture.tabID, previous: fixture.paneIDs[0]))
        #expect(
            transition.effect
                == .switchArrangement(
                    previous: .init(
                        layoutPaneIDs: fixture.paneIDs,
                        minimizedPaneIDs: [fixture.paneIDs[2]],
                        showsMinimizedPanes: true
                    ),
                    replacement: .init(
                        layoutPaneIDs: [fixture.paneIDs[1], fixture.paneIDs[2]],
                        minimizedPaneIDs: [fixture.paneIDs[2]],
                        showsMinimizedPanes: false
                    )
                )
        )
    }

    @Test("switch repairs a missing active arrangement cursor with an insertion")
    func switchRepairsMissingActiveArrangementCursor() {
        // Arrange
        let fixture = makeVisibilityFixture()
        let context = WorkspaceSwitchArrangementPlanningContext(
            tab: .present(fixture.tabState),
            activeArrangement: .missing,
            targetPaneCursor: fixture.paneCursor(fixture.customArrangementID),
            zoom: .notZoomed
        )

        // Act
        let decision = WorkspaceSwitchArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabID, arrangementID: fixture.customArrangementID),
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed switch transition")
            return
        }
        #expect(
            transition.activeArrangement
                == .insert(tabID: fixture.tabID, replacement: fixture.customArrangementID)
        )
        #expect(
            transition.activePane
                == .witness(
                    arrangementID: fixture.customArrangementID,
                    expected: .present(.selected(fixture.paneIDs[1]))
                )
        )
        #expect(transition.zoom == .witness(tabID: fixture.tabID, expected: .notZoomed))
    }

    @Test("switch explicitly repairs a dangling active arrangement cursor")
    func switchRepairsDanglingActiveArrangementCursor() {
        // Arrange
        let fixture = makeVisibilityFixture()
        let danglingArrangementID = UUIDv7.generate()
        let context = WorkspaceSwitchArrangementPlanningContext(
            tab: .present(fixture.tabState),
            activeArrangement: .selected(danglingArrangementID),
            targetPaneCursor: fixture.paneCursor(fixture.customArrangementID),
            zoom: fixture.zoom
        )

        // Act
        let decision = WorkspaceSwitchArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabID, arrangementID: fixture.customArrangementID),
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected dangling-cursor repair transition")
            return
        }
        #expect(
            transition.activeArrangement
                == .replace(
                    tabID: fixture.tabID,
                    previous: danglingArrangementID,
                    replacement: fixture.customArrangementID
                )
        )
        guard case .switchArrangement(let previous, _) = transition.effect else {
            Issue.record("expected switch-arrangement effect")
            return
        }
        #expect(previous.layoutPaneIDs == fixture.paneIDs)
    }

    @Test("switching to the current arrangement is a semantic no-op")
    func switchToCurrentArrangementIsUnchanged() {
        // Arrange
        let fixture = makeVisibilityFixture()

        // Act
        let decision = WorkspaceSwitchArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabID, arrangementID: fixture.defaultArrangementID),
            context: fixture.switchContext(targetArrangementID: fixture.defaultArrangementID)
        )

        // Assert
        #expect(decision == .unchanged)
    }

    @Test("shows-minimized replaces only the active arrangement graph")
    func showsMinimizedReplacesOnlyActiveArrangement() {
        // Arrange
        let fixture = makeVisibilityFixture()

        // Act
        let decision = WorkspaceSetShowsMinimizedPanesTransitionPlanner.plan(
            .init(tabID: fixture.tabID, showsMinimizedPanes: false),
            context: fixture.showsMinimizedContext
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed shows-minimized transition")
            return
        }
        guard case .replace(_, let previous, let replacement) = transition.tabGraph else {
            Issue.record("expected tab graph replacement")
            return
        }
        #expect(previous.arrangements[0].showsMinimizedPanes)
        #expect(!replacement.arrangements[0].showsMinimizedPanes)
        #expect(previous.arrangements[1] == replacement.arrangements[1])
        #expect(
            transition.activeArrangement
                == .witness(
                    tabID: fixture.tabID,
                    expected: .selected(fixture.defaultArrangementID)
                )
        )
        #expect(transition.activePane == .notRead)
        #expect(transition.zoom == .notRead)
    }

    @Test("minimize updates graph selection and zoom as one transition")
    func minimizeSelectedZoomedPaneUpdatesAllOwners() {
        // Arrange
        let fixture = makeVisibilityFixture()

        // Act
        let decision = WorkspaceMinimizePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[0]),
            context: fixture.minimizeContext
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed minimize transition")
            return
        }
        guard case .replace(_, _, let replacement) = transition.tabGraph else {
            Issue.record("expected tab graph replacement")
            return
        }
        #expect(replacement.arrangements[0].minimizedPaneIds == [fixture.paneIDs[0], fixture.paneIDs[2]])
        #expect(
            transition.activePane
                == .replace(
                    arrangementID: fixture.defaultArrangementID,
                    previous: fixture.paneIDs[0],
                    replacement: fixture.paneIDs[1]
                )
        )
        #expect(transition.zoom == .clear(tabID: fixture.tabID, previous: fixture.paneIDs[0]))
        #expect(transition.effect == .minimizePane(paneID: fixture.paneIDs[0]))
    }

    @Test("minimizing a non-selected pane witnesses the current selection")
    func minimizeNonSelectedPaneWitnessesSelection() {
        // Arrange
        let fixture = makeVisibilityFixture()

        // Act
        let decision = WorkspaceMinimizePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[1]),
            context: fixture.minimizeContext
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed minimize transition")
            return
        }
        #expect(
            transition.activePane
                == .witness(
                    arrangementID: fixture.defaultArrangementID,
                    expected: .present(.selected(fixture.paneIDs[0]))
                )
        )
    }

    @Test("minimizing the last visible pane removes its durable selection")
    func minimizeLastVisiblePaneRemovesSelection() {
        // Arrange
        let fixture = makeVisibilityFixture()
        var tabState = fixture.tabState
        tabState.arrangements[0].minimizedPaneIds = [fixture.paneIDs[1], fixture.paneIDs[2]]
        let context = WorkspaceMinimizePanePlanningContext(
            tab: .present(tabState),
            activeArrangementPaneCursor: fixture.activeArrangementPaneCursor,
            zoom: fixture.zoom
        )

        // Act
        let decision = WorkspaceMinimizePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[0]),
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed minimize transition")
            return
        }
        #expect(
            transition.activePane
                == .remove(
                    arrangementID: fixture.defaultArrangementID,
                    previous: fixture.paneIDs[0]
                )
        )
    }

    @Test("expand changes graph and selects the expanded pane")
    func expandSelectsExpandedPane() {
        // Arrange
        let fixture = makeVisibilityFixture()

        // Act
        let decision = WorkspaceExpandPaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[2]),
            context: fixture.expandContext
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed expand transition")
            return
        }
        guard case .replace(_, _, let replacement) = transition.tabGraph else {
            Issue.record("expected tab graph replacement")
            return
        }
        #expect(replacement.arrangements[0].minimizedPaneIds.isEmpty)
        #expect(
            transition.activePane
                == .replace(
                    arrangementID: fixture.defaultArrangementID,
                    previous: fixture.paneIDs[0],
                    replacement: fixture.paneIDs[2]
                )
        )
        #expect(transition.zoom == .notRead)
        #expect(transition.effect == .expandPane(paneID: fixture.paneIDs[2]))
    }

    @Test("missing ownership and semantic duplicates are explicit")
    func rejectionsAndNoOpsAreExplicit() {
        // Arrange
        let fixture = makeVisibilityFixture()
        let missingActiveContext = WorkspaceMinimizePanePlanningContext(
            tab: .present(fixture.tabState),
            activeArrangementPaneCursor: .missing,
            zoom: fixture.zoom
        )
        let missingPaneID = UUIDv7.generate()
        let missingTabID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceSetShowsMinimizedPanesTransitionPlanner.plan(
            .init(tabID: missingTabID, showsMinimizedPanes: false),
            context: .init(tab: .missing, activeArrangement: .missing)
        )
        let missingActive = WorkspaceMinimizePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[0]),
            context: missingActiveContext
        )
        let missingArrangement = WorkspaceSwitchArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabID, arrangementID: UUIDv7.generate()),
            context: fixture.switchContext(targetArrangementID: UUIDv7.generate())
        )
        let missingPane = WorkspaceExpandPaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: missingPaneID),
            context: fixture.expandContext
        )
        let alreadyShown = WorkspaceSetShowsMinimizedPanesTransitionPlanner.plan(
            .init(tabID: fixture.tabID, showsMinimizedPanes: true),
            context: fixture.showsMinimizedContext
        )
        let alreadyExpanded = WorkspaceExpandPaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[1]),
            context: fixture.expandContext
        )

        // Assert
        guard case .rejected(.missingTab) = missingTab else {
            Issue.record("expected missing-tab rejection")
            return
        }
        #expect(missingActive == .rejected(.missingActiveArrangement(fixture.tabID)))
        guard case .rejected(.missingArrangement) = missingArrangement else {
            Issue.record("expected missing-arrangement rejection")
            return
        }
        #expect(missingPane == .rejected(.paneNotOwnedByTab(tabID: fixture.tabID, paneID: missingPaneID)))
        #expect(alreadyShown == .unchanged)
        #expect(alreadyExpanded == .unchanged)
    }
}

struct ActiveArrangementVisibilityFixture {
    let tabID: UUID
    let defaultArrangementID: UUID
    let customArrangementID: UUID
    let paneIDs: [UUID]
    let tabState: TabGraphState
    let activeArrangement: WorkspaceActiveArrangementSelection
    let paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState]
    let zoom: WorkspaceZoomSelection

    var context: ActiveArrangementVisibilityFixtureContext {
        ActiveArrangementVisibilityFixtureContext(
            tabStates: [tabState],
            activeArrangementIDsByTabID: {
                guard case .selected(let arrangementID) = activeArrangement else { return [:] }
                return [tabID: arrangementID]
            }(),
            paneCursorsByArrangementID: paneCursorsByArrangementID,
            zoomedPaneIDsByTabID: {
                guard case .zoomed(let paneID) = zoom else { return [:] }
                return [tabID: paneID]
            }()
        )
    }

    func paneCursor(_ arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard let cursor = paneCursorsByArrangementID[arrangementID] else { return .missing }
        return .present(cursor.activePaneId.map(WorkspacePaneSelection.selected) ?? .noSelection)
    }

    func switchContext(
        targetArrangementID: UUID
    ) -> WorkspaceSwitchArrangementPlanningContext {
        WorkspaceSwitchArrangementPlanningContext(
            tab: .present(tabState),
            activeArrangement: activeArrangement,
            targetPaneCursor: paneCursor(targetArrangementID),
            zoom: zoom
        )
    }

    var showsMinimizedContext: WorkspaceSetShowsMinimizedPanesPlanningContext {
        WorkspaceSetShowsMinimizedPanesPlanningContext(
            tab: .present(tabState),
            activeArrangement: activeArrangement
        )
    }

    var activeArrangementPaneCursor: WorkspaceActiveArrangementPaneCursorWitness {
        switch activeArrangement {
        case .missing:
            return .missing
        case .selected(let arrangementID):
            return .selected(
                arrangementID: arrangementID,
                paneCursor: paneCursor(arrangementID)
            )
        }
    }

    var minimizeContext: WorkspaceMinimizePanePlanningContext {
        WorkspaceMinimizePanePlanningContext(
            tab: .present(tabState),
            activeArrangementPaneCursor: activeArrangementPaneCursor,
            zoom: zoom
        )
    }

    var expandContext: WorkspaceExpandPanePlanningContext {
        WorkspaceExpandPanePlanningContext(
            tab: .present(tabState),
            activeArrangementPaneCursor: activeArrangementPaneCursor
        )
    }
}

struct ActiveArrangementVisibilityFixtureContext {
    var tabStates: [TabGraphState]
    var activeArrangementIDsByTabID: [UUID: UUID]
    var paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState]
    var zoomedPaneIDsByTabID: [UUID: UUID]
}

func makeVisibilityFixture() -> ActiveArrangementVisibilityFixture {
    let paneIDs = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
    let tabID = UUIDv7.generate()
    let defaultArrangementID = UUIDv7.generate()
    let customArrangementID = UUIDv7.generate()
    let defaultArrangement = PaneArrangementGraphState(
        id: defaultArrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(
            panes: [
                .init(paneId: paneIDs[0], ratio: 0.34),
                .init(paneId: paneIDs[1], ratio: 0.33),
                .init(paneId: paneIDs[2], ratio: 0.33),
            ],
            dividerIds: [UUIDv7.generate(), UUIDv7.generate()]
        ),
        minimizedPaneIds: [paneIDs[2]],
        showsMinimizedPanes: true,
        drawerViews: [:]
    )
    let customArrangement = PaneArrangementGraphState(
        id: customArrangementID,
        name: "Focus",
        isDefault: false,
        layout: Layout(
            panes: [
                .init(paneId: paneIDs[1], ratio: 0.5),
                .init(paneId: paneIDs[2], ratio: 0.5),
            ],
            dividerIds: [UUIDv7.generate()]
        ),
        minimizedPaneIds: [paneIDs[2]],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
    let tabState = TabGraphState(
        tabId: tabID,
        allPaneIds: paneIDs,
        arrangements: [defaultArrangement, customArrangement]
    )
    return ActiveArrangementVisibilityFixture(
        tabID: tabID,
        defaultArrangementID: defaultArrangementID,
        customArrangementID: customArrangementID,
        paneIDs: paneIDs,
        tabState: tabState,
        activeArrangement: .selected(defaultArrangementID),
        paneCursorsByArrangementID: [
            defaultArrangementID: .init(activePaneId: paneIDs[0]),
            customArrangementID: .init(activePaneId: paneIDs[1]),
        ],
        zoom: .zoomed(paneIDs[0])
    )
}
