import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace active arrangement visibility transitions")
struct WorkspaceVisibilityTransitionTests {
    @Test("switch repairs the target pane cursor and clears transient zoom")
    func switchRepairsTargetCursorAndClearsZoom() {
        // Arrange
        let fixture = makeVisibilityFixture()
        var context = fixture.context
        context.paneCursorsByArrangementID[fixture.customArrangementID] = .init(
            activePaneId: fixture.paneIDs[2]
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
        var context = fixture.context
        context.activeArrangementIDsByTabID = [:]
        context.zoomedPaneIDsByTabID = [:]

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
        var context = fixture.context
        context.activeArrangementIDsByTabID[fixture.tabID] = danglingArrangementID

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
            context: fixture.context
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
            context: fixture.context
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
            context: fixture.context
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
            context: fixture.context
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
        var context = fixture.context
        context.tabStates[0].arrangements[0].minimizedPaneIds = [fixture.paneIDs[1], fixture.paneIDs[2]]

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
            context: fixture.context
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
        var missingActiveContext = fixture.context
        missingActiveContext.activeArrangementIDsByTabID = [:]
        let missingPaneID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceSetShowsMinimizedPanesTransitionPlanner.plan(
            .init(tabID: UUIDv7.generate(), showsMinimizedPanes: false),
            context: fixture.context
        )
        let missingActive = WorkspaceMinimizePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[0]),
            context: missingActiveContext
        )
        let missingArrangement = WorkspaceSwitchArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabID, arrangementID: UUIDv7.generate()),
            context: fixture.context
        )
        let missingPane = WorkspaceExpandPaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: missingPaneID),
            context: fixture.context
        )
        let alreadyShown = WorkspaceSetShowsMinimizedPanesTransitionPlanner.plan(
            .init(tabID: fixture.tabID, showsMinimizedPanes: true),
            context: fixture.context
        )
        let alreadyExpanded = WorkspaceExpandPaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[1]),
            context: fixture.context
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
    let context: WorkspaceVisibilityPlanningContext
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
        context: WorkspaceVisibilityPlanningContext(
            tabStates: [tabState],
            activeArrangementIDsByTabID: [tabID: defaultArrangementID],
            paneCursorsByArrangementID: [
                defaultArrangementID: .init(activePaneId: paneIDs[0]),
                customArrangementID: .init(activePaneId: paneIDs[1]),
            ],
            zoomedPaneIDsByTabID: [tabID: paneIDs[0]]
        )
    )
}
