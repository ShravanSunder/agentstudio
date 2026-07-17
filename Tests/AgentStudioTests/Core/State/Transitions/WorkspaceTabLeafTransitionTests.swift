import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace tab leaf transitions")
struct WorkspaceTabLeafTransitionTests {
    @Test("select tab approves an exact cursor replacement")
    func selectTabApprovesExactCursorReplacement() {
        // Arrange
        let firstTab = TabShell(id: UUIDv7.generate(), name: "First")
        let secondTab = TabShell(id: UUIDv7.generate(), name: "Second")
        let context = WorkspaceTabLeafPlanningContext(
            tabShells: [firstTab, secondTab],
            activeTab: .selected(firstTab.id)
        )

        // Act
        let decision = WorkspaceSelectTabTransitionPlanner.plan(
            WorkspaceSelectTabRequest(tabID: secondTab.id),
            context: context
        )

        // Assert
        #expect(
            decision
                == .changed(
                    WorkspaceTabCursorReplacement(
                        previous: .selected(firstTab.id),
                        replacement: .selected(secondTab.id)
                    )
                )
        )
    }

    @Test("selecting the active tab is unchanged and a missing tab is rejected")
    func selectTabNoOpAndRejectionAreExplicit() {
        // Arrange
        let tab = TabShell(id: UUIDv7.generate(), name: "Only")
        let context = WorkspaceTabLeafPlanningContext(
            tabShells: [tab],
            activeTab: .selected(tab.id)
        )
        let missingTabID = UUIDv7.generate()

        // Act
        let unchanged = WorkspaceSelectTabTransitionPlanner.plan(
            WorkspaceSelectTabRequest(tabID: tab.id),
            context: context
        )
        let rejected = WorkspaceSelectTabTransitionPlanner.plan(
            WorkspaceSelectTabRequest(tabID: missingTabID),
            context: context
        )

        // Assert
        #expect(unchanged == .unchanged)
        #expect(rejected == .rejected(.missingTab(missingTabID)))
    }

    @Test("rename tab normalizes once and approves the exact shell replacement")
    func renameTabApprovesExactNormalizedReplacement() {
        // Arrange
        let firstTab = TabShell(id: UUIDv7.generate(), name: "First", colorHex: "#ABCDEF")
        let secondTab = TabShell(id: UUIDv7.generate(), name: "Second")
        let context = WorkspaceTabLeafPlanningContext(
            tabShells: [firstTab, secondTab],
            activeTab: .selected(firstTab.id)
        )

        // Act
        let decision = WorkspaceRenameTabTransitionPlanner.plan(
            WorkspaceRenameTabRequest(tabID: firstTab.id, name: "  Renamed tab  "),
            context: context
        )

        // Assert
        var renamedTab = firstTab
        renamedTab.rename(to: "Renamed tab")
        guard case .changed(let transition) = decision else {
            Issue.record("expected an approved rename transition")
            return
        }
        #expect(transition.replacementTabShells == [renamedTab, secondTab])
        #expect(
            transition.affectedShells
                == [
                    WorkspaceIndexedTabShellReplacement(
                        previous: .init(index: 0, shell: firstTab),
                        replacement: .init(index: 0, shell: renamedTab)
                    )
                ]
        )
    }

    @Test("rename tab reports normalized no-op, empty name, and missing tab distinctly")
    func renameTabNoOpAndRejectionsAreExplicit() {
        // Arrange
        let tab = TabShell(id: UUIDv7.generate(), name: "Existing")
        let context = WorkspaceTabLeafPlanningContext(tabShells: [tab], activeTab: .selected(tab.id))
        let missingTabID = UUIDv7.generate()

        // Act
        let unchanged = WorkspaceRenameTabTransitionPlanner.plan(
            WorkspaceRenameTabRequest(tabID: tab.id, name: " Existing "),
            context: context
        )
        let empty = WorkspaceRenameTabTransitionPlanner.plan(
            WorkspaceRenameTabRequest(tabID: tab.id, name: " \n "),
            context: context
        )
        let missing = WorkspaceRenameTabTransitionPlanner.plan(
            WorkspaceRenameTabRequest(tabID: missingTabID, name: "New"),
            context: context
        )

        // Assert
        #expect(unchanged == .unchanged)
        #expect(empty == .rejected(.emptyTabName(tab.id)))
        #expect(missing == .rejected(.missingTab(missingTabID)))
    }

    @Test("move by delta describes every displaced shell in one approved replacement")
    func moveByDeltaDescribesEveryAffectedShell() {
        // Arrange
        let tabs = makeTabShells(named: ["A", "B", "C", "D"])
        let context = WorkspaceTabLeafPlanningContext(
            tabShells: tabs,
            activeTab: .selected(tabs[1].id)
        )

        // Act
        let decision = WorkspaceMoveTabByDeltaTransitionPlanner.plan(
            WorkspaceMoveTabByDeltaRequest(tabID: tabs[0].id, delta: 3),
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected an approved delta movement")
            return
        }
        #expect(transition.replacementTabShells == [tabs[1], tabs[2], tabs[3], tabs[0]])
        #expect(
            transition.affectedShells
                == [
                    indexedReplacement(tabs[0], from: 0, to: 3),
                    indexedReplacement(tabs[1], from: 1, to: 0),
                    indexedReplacement(tabs[2], from: 2, to: 1),
                    indexedReplacement(tabs[3], from: 3, to: 2),
                ]
        )
    }

    @Test("move by delta clamps safely and reports boundary no-ops")
    func moveByDeltaClampsAndReportsNoOp() {
        // Arrange
        let tabs = makeTabShells(named: ["A", "B", "C"])
        let context = WorkspaceTabLeafPlanningContext(tabShells: tabs, activeTab: .selected(tabs[1].id))
        let missingTabID = UUIDv7.generate()

        // Act
        let clamped = WorkspaceMoveTabByDeltaTransitionPlanner.plan(
            WorkspaceMoveTabByDeltaRequest(tabID: tabs[2].id, delta: Int.min),
            context: context
        )
        let unchanged = WorkspaceMoveTabByDeltaTransitionPlanner.plan(
            WorkspaceMoveTabByDeltaRequest(tabID: tabs[0].id, delta: -1),
            context: context
        )
        let missing = WorkspaceMoveTabByDeltaTransitionPlanner.plan(
            WorkspaceMoveTabByDeltaRequest(tabID: missingTabID, delta: 1),
            context: context
        )

        // Assert
        guard case .changed(let transition) = clamped else {
            Issue.record("expected clamped movement to produce a transition")
            return
        }
        #expect(transition.replacementTabShells == [tabs[2], tabs[0], tabs[1]])
        #expect(transition.affectedShells.count == 3)
        #expect(unchanged == .unchanged)
        #expect(missing == .rejected(.missingTab(missingTabID)))
    }

    @Test("reorder and select combines every shifted shell and cursor replacement")
    func reorderAndSelectProducesOneCombinedTransition() {
        // Arrange
        let tabs = makeTabShells(named: ["A", "B", "C", "D"])
        let context = WorkspaceTabLeafPlanningContext(
            tabShells: tabs,
            activeTab: .selected(tabs[3].id)
        )

        // Act
        let decision = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: tabs[0].id, toIndex: 3),
            context: context
        )

        // Assert
        guard case .changed(.shellAndCursor(let shellTransition, let cursorReplacement)) = decision else {
            Issue.record("expected one combined shell-and-cursor transition")
            return
        }
        #expect(shellTransition.replacementTabShells == [tabs[1], tabs[2], tabs[0], tabs[3]])
        #expect(
            shellTransition.affectedShells
                == [
                    indexedReplacement(tabs[0], from: 0, to: 2),
                    indexedReplacement(tabs[1], from: 1, to: 0),
                    indexedReplacement(tabs[2], from: 2, to: 1),
                ]
        )
        #expect(
            cursorReplacement
                == WorkspaceTabCursorReplacement(
                    previous: .selected(tabs[3].id),
                    replacement: .selected(tabs[0].id)
                )
        )
    }

    @Test("reorder and select has strict shell-only, cursor-only, and unchanged variants")
    func reorderAndSelectVariantsAreExplicit() {
        // Arrange
        let tabs = makeTabShells(named: ["A", "B", "C"])

        // Act
        let shellOnly = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: tabs[0].id, toIndex: 2),
            context: .init(tabShells: tabs, activeTab: .selected(tabs[0].id))
        )
        let cursorOnly = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: tabs[1].id, toIndex: 1),
            context: .init(tabShells: tabs, activeTab: .selected(tabs[0].id))
        )
        let unchanged = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: tabs[1].id, toIndex: 1),
            context: .init(tabShells: tabs, activeTab: .selected(tabs[1].id))
        )

        // Assert
        guard case .changed(.shellOnly(let shellTransition)) = shellOnly else {
            Issue.record("expected a shell-only reorder")
            return
        }
        #expect(shellTransition.replacementTabShells == [tabs[1], tabs[0], tabs[2]])
        #expect(
            cursorOnly
                == .changed(
                    .cursorOnly(
                        WorkspaceTabCursorReplacement(
                            previous: .selected(tabs[0].id),
                            replacement: .selected(tabs[1].id)
                        )
                    )
                )
        )
        #expect(unchanged == .unchanged)
    }

    @Test("reorder and select rejects missing tabs and invalid insertion boundaries")
    func reorderAndSelectRejectionsAreExplicit() {
        // Arrange
        let tabs = makeTabShells(named: ["A", "B"])
        let context = WorkspaceTabLeafPlanningContext(tabShells: tabs, activeTab: .selected(tabs[0].id))
        let missingTabID = UUIDv7.generate()

        // Act
        let missing = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: missingTabID, toIndex: 0),
            context: context
        )
        let negative = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: tabs[0].id, toIndex: -1),
            context: context
        )
        let pastEnd = WorkspaceReorderAndSelectTabTransitionPlanner.plan(
            WorkspaceReorderAndSelectTabRequest(tabID: tabs[0].id, toIndex: tabs.count),
            context: context
        )

        // Assert
        #expect(missing == .rejected(.missingTab(missingTabID)))
        #expect(negative == .rejected(.invalidReorderIndex(-1)))
        #expect(pastEnd == .rejected(.invalidReorderIndex(tabs.count)))
    }
}

private func makeTabShells(named names: [String]) -> [TabShell] {
    names.map { TabShell(id: UUIDv7.generate(), name: $0) }
}

private func indexedReplacement(
    _ shell: TabShell,
    from previousIndex: Int,
    to replacementIndex: Int
) -> WorkspaceIndexedTabShellReplacement {
    WorkspaceIndexedTabShellReplacement(
        previous: .init(index: previousIndex, shell: shell),
        replacement: .init(index: replacementIndex, shell: shell)
    )
}
