import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace arrangement selection transition applier")
struct ArrangementSelectionTransitionApplierTests {
    @Test("active pane applies one keyed cursor and preserves every unrelated owner")
    func appliesActivePaneOnly() throws {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let atoms = makeArrangementSelectionAtoms(fixture)
        let applier = makeArrangementSelectionApplier(atoms)
        let transition = try requireActivePaneSelectionTransition(fixture)
        let graphBefore = atoms.graph.tabStates
        let drawerBefore = atoms.cursor.drawerCursorsByKey
        let unrelatedPaneBefore = atoms.cursor.paneCursorsByArrangementId[fixture.inactiveArrangementID]
        let presentationBefore = atoms.presentation.zoomedPaneIdsByTabId

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(
            atoms.cursor.activePaneId(forArrangement: fixture.activeArrangementID)
                == fixture.mainPaneIDs[1]
        )
        #expect(atoms.graph.tabStates == graphBefore)
        #expect(atoms.cursor.drawerCursorsByKey == drawerBefore)
        #expect(atoms.cursor.paneCursorsByArrangementId[fixture.inactiveArrangementID] == unrelatedPaneBefore)
        #expect(atoms.presentation.zoomedPaneIdsByTabId == presentationBefore)
    }

    @Test("active drawer child applies one keyed cursor and preserves every unrelated owner")
    func appliesActiveDrawerChildOnly() throws {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let atoms = makeArrangementSelectionAtoms(fixture)
        let applier = makeArrangementSelectionApplier(atoms)
        let transition = try requireActiveDrawerSelectionTransition(fixture)
        let graphBefore = atoms.graph.tabStates
        let paneBefore = atoms.cursor.paneCursorsByArrangementId
        let presentationBefore = atoms.presentation.zoomedPaneIdsByTabId

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(
            atoms.cursor.activeChildId(
                forArrangement: fixture.activeArrangementID,
                drawerId: fixture.drawerID
            ) == fixture.drawerChildIDs[1]
        )
        #expect(atoms.graph.tabStates == graphBefore)
        #expect(atoms.cursor.paneCursorsByArrangementId == paneBefore)
        #expect(atoms.presentation.zoomedPaneIdsByTabId == presentationBefore)
    }

    @Test("stale graph arrangement and cursor witnesses reject before mutation")
    func staleWitnessesReject() throws {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let graphAtoms = makeArrangementSelectionAtoms(fixture)
        let graphApplier = makeArrangementSelectionApplier(graphAtoms)
        let paneTransition = try requireActivePaneSelectionTransition(fixture)
        var staleGraph = fixture.tabState
        staleGraph.arrangements[0].name = "External"
        graphAtoms.graph.replaceTabStates([staleGraph])

        let arrangementAtoms = makeArrangementSelectionAtoms(fixture)
        let arrangementApplier = makeArrangementSelectionApplier(arrangementAtoms)
        arrangementAtoms.cursor.setActiveArrangementId(fixture.inactiveArrangementID, forTab: fixture.tabID)

        let cursorAtoms = makeArrangementSelectionAtoms(fixture)
        let cursorApplier = makeArrangementSelectionApplier(cursorAtoms)
        cursorAtoms.cursor.setPaneCursor(
            .init(activePaneId: fixture.mainPaneIDs[1]),
            forArrangement: fixture.activeArrangementID
        )

        // Act
        let staleGraphResult = graphApplier.apply(paneTransition)
        let staleArrangementResult = arrangementApplier.apply(paneTransition)
        let staleCursorResult = cursorApplier.apply(paneTransition)

        // Assert
        #expect(
            staleGraphResult
                == .rejected(
                    .staleTabGraph(
                        tabID: fixture.tabID,
                        expected: fixture.tabState,
                        actual: .present(staleGraph)
                    )
                )
        )
        #expect(
            staleArrangementResult
                == .rejected(
                    .staleActiveArrangement(
                        tabID: fixture.tabID,
                        expected: .selected(fixture.activeArrangementID),
                        actual: .selected(fixture.inactiveArrangementID)
                    )
                )
        )
        #expect(
            staleCursorResult
                == .rejected(
                    .staleActivePane(
                        arrangementID: fixture.activeArrangementID,
                        expected: .present(.selected(fixture.mainPaneIDs[0])),
                        actual: .present(.selected(fixture.mainPaneIDs[1]))
                    )
                )
        )
        #expect(
            graphAtoms.cursor.activePaneId(forArrangement: fixture.activeArrangementID)
                == fixture.mainPaneIDs[0]
        )
        #expect(
            arrangementAtoms.cursor.activePaneId(forArrangement: fixture.activeArrangementID)
                == fixture.mainPaneIDs[0]
        )
    }

    @Test("stale drawer cursor rejects with zero mutation")
    func staleDrawerCursorRejectsWithoutMutation() throws {
        // Arrange
        let fixture = makeArrangementSelectionFixture()
        let atoms = makeArrangementSelectionAtoms(fixture)
        let applier = makeArrangementSelectionApplier(atoms)
        let transition = try requireActiveDrawerSelectionTransition(fixture)
        atoms.cursor.setDrawerCursor(
            .init(activeChildId: fixture.drawerChildIDs[1]),
            for: fixture.drawerCursorKey
        )
        let graphBefore = atoms.graph.tabStates
        let arrangementsBefore = atoms.cursor.activeArrangementIdsByTabId
        let panesBefore = atoms.cursor.paneCursorsByArrangementId
        let drawersBefore = atoms.cursor.drawerCursorsByKey

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleActiveDrawerChild(
                        key: fixture.drawerCursorKey,
                        expected: .present(.selected(fixture.drawerChildIDs[0])),
                        actual: .present(.selected(fixture.drawerChildIDs[1]))
                    )
                )
        )
        #expect(atoms.graph.tabStates == graphBefore)
        #expect(atoms.cursor.activeArrangementIdsByTabId == arrangementsBefore)
        #expect(atoms.cursor.paneCursorsByArrangementId == panesBefore)
        #expect(atoms.cursor.drawerCursorsByKey == drawersBefore)
    }
}

struct ArrangementSelectionAtoms {
    let graph: WorkspaceTabGraphAtom
    let cursor: WorkspaceArrangementCursorAtom
    let presentation: WorkspacePanePresentationAtom
}

@MainActor
func makeArrangementSelectionAtoms(_ fixture: ArrangementSelectionFixture) -> ArrangementSelectionAtoms {
    let graph = WorkspaceTabGraphAtom()
    let cursor = WorkspaceArrangementCursorAtom()
    let presentation = WorkspacePanePresentationAtom()
    graph.replaceTabStates([fixture.tabState])
    cursor.replaceCursors(
        activeArrangementIdsByTabId: [fixture.tabID: fixture.activeArrangementID],
        paneCursorsByArrangementId: [
            fixture.activeArrangementID: .init(activePaneId: fixture.mainPaneIDs[0]),
            fixture.inactiveArrangementID: .init(activePaneId: fixture.inactivePaneID),
        ],
        drawerCursorsByKey: [
            fixture.drawerCursorKey: .init(activeChildId: fixture.drawerChildIDs[0])
        ]
    )
    presentation.setZoomedPaneId(fixture.mainPaneIDs[0], forTab: fixture.tabID)
    return .init(graph: graph, cursor: cursor, presentation: presentation)
}

@MainActor
private func makeArrangementSelectionApplier(
    _ atoms: ArrangementSelectionAtoms
) -> WorkspaceArrangementSelectionTransitionApplier {
    WorkspaceArrangementSelectionTransitionApplier(
        workspaceTabGraphAtom: atoms.graph,
        workspaceArrangementCursorAtom: atoms.cursor
    )
}

private func requireActivePaneSelectionTransition(
    _ fixture: ArrangementSelectionFixture
) throws -> WorkspaceArrangementSelectionTransition {
    let decision = WorkspaceSetActivePaneTransitionPlanner.plan(
        .init(tabID: fixture.tabID, selection: .selected(fixture.mainPaneIDs[1])),
        context: fixture.activePaneContext
    )
    guard case .changed(let transition) = decision else {
        throw WorkspaceArrangementSelectionTestError.expectedTransition
    }
    return transition
}

private func requireActiveDrawerSelectionTransition(
    _ fixture: ArrangementSelectionFixture
) throws -> WorkspaceArrangementSelectionTransition {
    let decision = WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
        .init(
            tabID: fixture.tabID,
            drawerID: fixture.drawerID,
            childPaneID: fixture.drawerChildIDs[1]
        ),
        context: fixture.activeDrawerContext
    )
    guard case .changed(let transition) = decision else {
        throw WorkspaceArrangementSelectionTestError.expectedTransition
    }
    return transition
}

private enum WorkspaceArrangementSelectionTestError: Error {
    case expectedTransition
}
