import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace tab graph leaf transition applier")
struct WorkspaceTabGraphLeafTransitionApplierTests {
    @Test("stale graph rejects before replacement")
    func staleGraphRejectsWithoutMutation() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        graphAtom.replaceTabStates([fixture.tabState])
        cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let applier = WorkspaceTabGraphLeafTransitionApplier(
            workspaceTabGraphAtom: graphAtom,
            workspaceArrangementCursorAtom: cursorAtom
        )
        let transition = try requireEqualizeTransition(fixture)
        var externalState = fixture.tabState
        externalState.arrangements[1].name = "External"
        graphAtom.replaceTabStates([externalState])

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .rejected(.staleTabGraphs(expected: [fixture.tabState], actual: [externalState])))
        #expect(graphAtom.tabStates == [externalState])
    }

    @Test("stale active arrangement rejects equalize before graph mutation")
    func staleActiveArrangementRejectsWithoutMutation() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        graphAtom.replaceTabStates([fixture.tabState])
        cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let applier = WorkspaceTabGraphLeafTransitionApplier(
            workspaceTabGraphAtom: graphAtom,
            workspaceArrangementCursorAtom: cursorAtom
        )
        let transition = try requireEqualizeTransition(fixture)
        cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.defaultArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleActiveArrangement(
                        tabID: fixture.tabState.tabId,
                        expected: .selected(fixture.customArrangementID),
                        actual: .selected(fixture.defaultArrangementID)
                    )
                )
        )
        #expect(graphAtom.tabStates == [fixture.tabState])
    }

    @Test("rename graph-only witness ignores unrelated cursor change")
    func renameIgnoresUnrelatedCursorChange() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        graphAtom.replaceTabStates([fixture.tabState])
        let applier = WorkspaceTabGraphLeafTransitionApplier(
            workspaceTabGraphAtom: graphAtom,
            workspaceArrangementCursorAtom: cursorAtom
        )
        let transition = try requireRenameTransition(fixture)
        cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.defaultArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(graphAtom.tabStates[0].arrangements[1].name == "Renamed")
    }
}

private func requireEqualizeTransition(
    _ fixture: TabGraphLeafFixture
) throws -> WorkspaceTabGraphLeafTransition {
    let decision = WorkspaceEqualizePanesTransitionPlanner.plan(
        .init(tabID: fixture.tabState.tabId),
        tabStates: [fixture.tabState],
        activeArrangement: .selected(fixture.customArrangementID)
    )
    guard case .changed(let transition) = decision else {
        throw WorkspaceTabGraphLeafApplierTestError.expectedTransition
    }
    return transition
}

private func requireRenameTransition(
    _ fixture: TabGraphLeafFixture
) throws -> WorkspaceTabGraphLeafTransition {
    let decision = WorkspaceRenameArrangementTransitionPlanner.plan(
        .init(tabID: fixture.tabState.tabId, arrangementID: fixture.customArrangementID, name: "Renamed"),
        tabStates: [fixture.tabState]
    )
    guard case .changed(let transition) = decision else {
        throw WorkspaceTabGraphLeafApplierTestError.expectedTransition
    }
    return transition
}

private enum WorkspaceTabGraphLeafApplierTestError: Error {
    case expectedTransition
}
