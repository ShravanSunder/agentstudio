import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace visibility transition applier")
struct WorkspaceVisibilityTransitionApplierTests {
    @Test("applies graph cursor and presentation replacements together")
    func appliesAllOwners() throws {
        // Arrange
        let fixture = makeVisibilityFixture()
        let atoms = makeVisibilityAtoms(fixture)
        let applier = makeVisibilityApplier(atoms)
        let transition = try requireMinimizeVisibilityTransition(fixture)

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(
            atoms.graph.tabState(fixture.tabID)?.arrangements[0].minimizedPaneIds
                == [fixture.paneIDs[0], fixture.paneIDs[2]]
        )
        #expect(
            atoms.cursor.activePaneId(forArrangement: fixture.defaultArrangementID)
                == fixture.paneIDs[1]
        )
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tabID) == nil)
    }

    @Test("rejects stale graph before mutating any owner")
    func rejectsStaleGraph() throws {
        // Arrange
        let fixture = makeVisibilityFixture()
        let atoms = makeVisibilityAtoms(fixture)
        let applier = makeVisibilityApplier(atoms)
        let transition = try requireMinimizeVisibilityTransition(fixture)
        var staleGraph = fixture.context.tabStates[0]
        staleGraph.arrangements[0].name = "External"
        atoms.graph.replaceTabStates([staleGraph])

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleTabGraph(
                        tabID: fixture.tabID,
                        expected: fixture.context.tabStates[0],
                        actual: .present(staleGraph)
                    )
                )
        )
        #expect(
            atoms.cursor.activePaneId(forArrangement: fixture.defaultArrangementID)
                == fixture.paneIDs[0]
        )
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tabID) == fixture.paneIDs[0])
    }

    @Test("rejects stale cursor and zoom witnesses")
    func rejectsStaleCursorAndZoom() throws {
        // Arrange
        let fixture = makeVisibilityFixture()
        let cursorAtoms = makeVisibilityAtoms(fixture)
        let cursorApplier = makeVisibilityApplier(cursorAtoms)
        let transition = try requireMinimizeVisibilityTransition(fixture)
        var cursors = fixture.context.paneCursorsByArrangementID
        cursors[fixture.defaultArrangementID] = .init(activePaneId: fixture.paneIDs[1])
        cursorAtoms.cursor.replaceCursors(
            activeArrangementIdsByTabId: fixture.context.activeArrangementIDsByTabID,
            paneCursorsByArrangementId: cursors,
            drawerCursorsByKey: [:]
        )
        let zoomAtoms = makeVisibilityAtoms(fixture)
        let zoomApplier = makeVisibilityApplier(zoomAtoms)
        zoomAtoms.presentation.setZoomedPaneId(fixture.paneIDs[1], forTab: fixture.tabID)

        // Act
        let staleCursor = cursorApplier.apply(transition)
        let staleZoom = zoomApplier.apply(transition)

        // Assert
        #expect(
            staleCursor
                == .rejected(
                    .staleActivePane(
                        arrangementID: fixture.defaultArrangementID,
                        expected: .present(.selected(fixture.paneIDs[0])),
                        actual: .present(.selected(fixture.paneIDs[1]))
                    )
                )
        )
        #expect(
            staleZoom
                == .rejected(
                    .staleZoom(
                        tabID: fixture.tabID,
                        expected: .zoomed(fixture.paneIDs[0]),
                        actual: .zoomed(fixture.paneIDs[1])
                    )
                )
        )
    }

    @Test("non-target minimize rejects when that pane becomes selected before apply")
    func nonTargetMinimizeRejectsSelectionRace() throws {
        // Arrange
        let fixture = makeVisibilityFixture()
        let atoms = makeVisibilityAtoms(fixture)
        let applier = makeVisibilityApplier(atoms)
        let decision = WorkspaceMinimizePaneTransitionPlanner.plan(
            .init(tabID: fixture.tabID, paneID: fixture.paneIDs[1]),
            context: fixture.context
        )
        guard case .changed(let transition) = decision else {
            Issue.record("expected changed minimize transition")
            return
        }
        atoms.cursor.setPaneCursor(
            .init(activePaneId: fixture.paneIDs[1]),
            forArrangement: fixture.defaultArrangementID
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleActivePane(
                        arrangementID: fixture.defaultArrangementID,
                        expected: .present(.selected(fixture.paneIDs[0])),
                        actual: .present(.selected(fixture.paneIDs[1]))
                    )
                )
        )
        #expect(
            atoms.graph.tabState(fixture.tabID)?.arrangements[0].minimizedPaneIds
                == [fixture.paneIDs[2]]
        )
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tabID) == fixture.paneIDs[0])
    }

    @Test("unrelated owner changes do not invalidate a prepared transition")
    func unrelatedChangesRemainIndependent() throws {
        // Arrange
        let fixture = makeVisibilityFixture()
        let atoms = makeVisibilityAtoms(fixture)
        let applier = makeVisibilityApplier(atoms)
        let transition = try requireMinimizeVisibilityTransition(fixture)
        let unrelatedTabID = UUIDv7.generate()
        let unrelatedArrangementID = UUIDv7.generate()
        var activeArrangements = fixture.context.activeArrangementIDsByTabID
        activeArrangements[unrelatedTabID] = unrelatedArrangementID
        var paneCursors = fixture.context.paneCursorsByArrangementID
        paneCursors[unrelatedArrangementID] = .init(activePaneId: UUIDv7.generate())
        atoms.cursor.replaceCursors(
            activeArrangementIdsByTabId: activeArrangements,
            paneCursorsByArrangementId: paneCursors,
            drawerCursorsByKey: [:]
        )
        atoms.presentation.setZoomedPaneId(UUIDv7.generate(), forTab: unrelatedTabID)

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(atoms.cursor.activeArrangementId(forTab: unrelatedTabID) == unrelatedArrangementID)
        #expect(atoms.presentation.zoomedPaneId(forTab: unrelatedTabID) != nil)
    }
}

struct VisibilityAtomFixture {
    let graph: WorkspaceTabGraphAtom
    let cursor: WorkspaceArrangementCursorAtom
    let presentation: WorkspacePanePresentationAtom
}

@MainActor
func makeVisibilityAtoms(_ fixture: ActiveArrangementVisibilityFixture) -> VisibilityAtomFixture {
    let graph = WorkspaceTabGraphAtom()
    let cursor = WorkspaceArrangementCursorAtom()
    let presentation = WorkspacePanePresentationAtom()
    graph.replaceTabStates(fixture.context.tabStates)
    cursor.replaceCursors(
        activeArrangementIdsByTabId: fixture.context.activeArrangementIDsByTabID,
        paneCursorsByArrangementId: fixture.context.paneCursorsByArrangementID,
        drawerCursorsByKey: [:]
    )
    for (tabID, paneID) in fixture.context.zoomedPaneIDsByTabID {
        presentation.setZoomedPaneId(paneID, forTab: tabID)
    }
    return VisibilityAtomFixture(graph: graph, cursor: cursor, presentation: presentation)
}

@MainActor
private func makeVisibilityApplier(
    _ atoms: VisibilityAtomFixture
) -> WorkspaceVisibilityTransitionApplier {
    WorkspaceVisibilityTransitionApplier(
        workspaceTabGraphAtom: atoms.graph,
        workspaceArrangementCursorAtom: atoms.cursor,
        workspacePanePresentationAtom: atoms.presentation
    )
}

private func requireMinimizeVisibilityTransition(
    _ fixture: ActiveArrangementVisibilityFixture
) throws -> WorkspaceActiveArrangementVisibilityTransition {
    let decision = WorkspaceMinimizePaneTransitionPlanner.plan(
        .init(tabID: fixture.tabID, paneID: fixture.paneIDs[0]),
        context: fixture.context
    )
    guard case .changed(let transition) = decision else {
        throw WorkspaceVisibilityApplierTestError.expectedTransition
    }
    return transition
}

private enum WorkspaceVisibilityApplierTestError: Error {
    case expectedTransition
}
