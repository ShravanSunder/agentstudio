import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace tab leaf transition applier")
struct WorkspaceTabLeafTransitionApplierTests {
    @Test("combined transition verifies both owners before one application")
    func combinedTransitionAppliesBothOwners() throws {
        // Arrange
        let shells = makeApplierTabShells()
        let shellAtom = WorkspaceTabShellAtom()
        let cursorAtom = shellAtom.cursorAtom
        shellAtom.replaceTabShells(shells)
        cursorAtom.replaceActiveTab(shells[2].id)
        let applier = WorkspaceTabLeafTransitionApplier(
            workspaceTabShellAtom: shellAtom,
            workspaceTabCursorAtom: cursorAtom
        )
        let transition = try requireCombinedTransition(
            WorkspaceReorderAndSelectTabTransitionPlanner.plan(
                .init(tabID: shells[0].id, toIndex: 2),
                context: .init(tabShells: shells, activeTab: .selected(shells[2].id))
            )
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(shellAtom.tabShells == [shells[1], shells[0], shells[2]])
        #expect(cursorAtom.activeTabId == shells[0].id)
    }

    @Test("stale cursor rejects a combined transition before shell mutation")
    func staleCursorRejectsWithoutPartialMutation() throws {
        // Arrange
        let shells = makeApplierTabShells()
        let shellAtom = WorkspaceTabShellAtom()
        let cursorAtom = shellAtom.cursorAtom
        shellAtom.replaceTabShells(shells)
        cursorAtom.replaceActiveTab(shells[2].id)
        let applier = WorkspaceTabLeafTransitionApplier(
            workspaceTabShellAtom: shellAtom,
            workspaceTabCursorAtom: cursorAtom
        )
        let transition = try requireCombinedTransition(
            WorkspaceReorderAndSelectTabTransitionPlanner.plan(
                .init(tabID: shells[0].id, toIndex: 2),
                context: .init(tabShells: shells, activeTab: .selected(shells[2].id))
            )
        )
        cursorAtom.replaceActiveTab(shells[1].id)

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleCursor(
                        expected: .selected(shells[2].id),
                        actual: .selected(shells[1].id)
                    )
                )
        )
        #expect(shellAtom.tabShells == shells)
        #expect(cursorAtom.activeTabId == shells[1].id)
    }

    @Test("stale indexed shell rejects before replacement")
    func staleShellRejectsWithoutMutation() throws {
        // Arrange
        let shells = makeApplierTabShells()
        let shellAtom = WorkspaceTabShellAtom()
        let cursorAtom = shellAtom.cursorAtom
        shellAtom.replaceTabShells(shells)
        cursorAtom.replaceActiveTab(shells[0].id)
        let applier = WorkspaceTabLeafTransitionApplier(
            workspaceTabShellAtom: shellAtom,
            workspaceTabCursorAtom: cursorAtom
        )
        let transition = try requireShellTransition(
            WorkspaceRenameTabTransitionPlanner.plan(
                .init(tabID: shells[1].id, name: "Renamed"),
                context: .init(tabShells: shells, activeTab: .selected(shells[0].id))
            )
        )
        var externallyChangedShells = shells
        externallyChangedShells[1].rename(to: "External")
        shellAtom.replaceTabShells(externallyChangedShells)

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .rejected(.staleShells(expected: shells, actual: externallyChangedShells)))
        #expect(shellAtom.tabShells == externallyChangedShells)
    }
}

private func makeApplierTabShells() -> [TabShell] {
    ["A", "B", "C"].map { TabShell(id: UUIDv7.generate(), name: $0) }
}

private func requireCombinedTransition(
    _ decision: WorkspaceReorderAndSelectTabTransitionDecision
) throws -> WorkspaceReorderAndSelectTabTransition {
    guard case .changed(let transition) = decision else {
        throw WorkspaceTabLeafApplierTestError.expectedTransition
    }
    return transition
}

private func requireShellTransition(
    _ decision: WorkspaceRenameTabTransitionDecision
) throws -> WorkspaceTabShellCollectionTransition {
    guard case .changed(let transition) = decision else {
        throw WorkspaceTabLeafApplierTestError.expectedTransition
    }
    return transition
}

private enum WorkspaceTabLeafApplierTestError: Error {
    case expectedTransition
}
