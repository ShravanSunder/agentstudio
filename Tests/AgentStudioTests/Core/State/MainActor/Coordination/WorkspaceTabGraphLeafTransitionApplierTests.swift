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
        #expect(
            result
                == .rejected(
                    .staleTabGraph(
                        tabID: fixture.tabState.tabId,
                        expected: fixture.tabState,
                        actual: .present(externalState)
                    )
                )
        )
        #expect(graphAtom.tabStates == [externalState])
    }

    @Test("missing target graph rejects before replacement")
    func missingTargetGraphRejectsWithoutMutation() throws {
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
        graphAtom.replaceTabStates([])

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleTabGraph(
                        tabID: fixture.tabState.tabId,
                        expected: fixture.tabState,
                        actual: .missing
                    )
                )
        )
        #expect(graphAtom.tabStates.isEmpty)
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

    @Test("unrelated tab mutation does not stale or rewrite a target transition")
    func unrelatedTabMutationIsIgnored() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let unrelatedFixtures = (0..<256).map { _ in makeTabGraphLeafFixture() }
        let unrelatedTabs = unrelatedFixtures.map(\.tabState)
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        graphAtom.replaceTabStates(unrelatedTabs + [fixture.tabState])
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
        var unrelatedMutation = unrelatedTabs[127]
        unrelatedMutation.arrangements[1].name = "Concurrent unrelated change"
        graphAtom.replaceTabStatePreservingIdentity(unrelatedMutation)

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(graphAtom.tabState(unrelatedMutation.tabId) == unrelatedMutation)
        #expect(Array(graphAtom.tabStates.prefix(127)) == Array(unrelatedTabs.prefix(127)))
        #expect(Array(graphAtom.tabStates.dropFirst(128).prefix(128)) == Array(unrelatedTabs.dropFirst(128)))
        for unrelatedFixture in unrelatedFixtures {
            for arrangement in unrelatedFixture.tabState.arrangements {
                #expect(
                    graphAtom.tabID(containingArrangement: arrangement.id)
                        == unrelatedFixture.tabState.tabId
                )
            }
            for paneID in unrelatedFixture.tabState.allPaneIds {
                #expect(graphAtom.tabID(containingPane: paneID) == unrelatedFixture.tabState.tabId)
            }
        }
        #expect(graphAtom.tabState(fixture.tabState.tabId)?.arrangements[1].layout.panes.map(\.ratio) == [0.5, 0.5])
    }
}

private func requireEqualizeTransition(
    _ fixture: TabGraphLeafFixture
) throws -> WorkspaceTabGraphLeafTransition {
    let decision = WorkspaceEqualizePanesTransitionPlanner.plan(
        .init(tabID: fixture.tabState.tabId),
        context: .present(fixture.tabState),
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
        context: .present(fixture.tabState)
    )
    guard case .changed(let transition) = decision else {
        throw WorkspaceTabGraphLeafApplierTestError.expectedTransition
    }
    return transition
}

private enum WorkspaceTabGraphLeafApplierTestError: Error {
    case expectedTransition
}
