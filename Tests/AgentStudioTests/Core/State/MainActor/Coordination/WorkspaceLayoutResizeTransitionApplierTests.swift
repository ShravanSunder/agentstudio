import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace layout resize transition applier")
struct WorkspaceLayoutResizeTransitionApplierTests {
    @Test("applier replaces only the keyed tab and rejects stale graph")
    func keyedApplyAndStaleRejection() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let unrelatedTabs = (0..<256).map { _ in makeTabGraphLeafFixture().tabState }
        let registry = AtomRegistry()
        registry.workspaceTabGraph.replaceTabStates(unrelatedTabs + [fixture.tabState])
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let splitID = fixture.tabState.arrangements[1].layout.dividerIds[0]
        let decision = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: splitID,
                ratio: 0.4
            ),
            context: .selectedActiveArrangement(
                tab: fixture.tabState,
                arrangementID: fixture.customArrangementID
            )
        )
        guard case .changed(let transition) = decision else {
            Issue.record("expected resize transition")
            return
        }
        let applier = WorkspaceLayoutResizeTransitionApplier(
            workspaceTabGraphAtom: registry.workspaceTabGraph,
            workspaceArrangementCursorAtom: registry.workspaceArrangementCursor
        )

        // Act
        let applied = applier.apply(transition)
        let stale = applier.apply(transition)

        // Assert
        #expect(applied == .applied)
        #expect(Array(registry.workspaceTabGraph.tabStates.prefix(256)) == unrelatedTabs)
        guard case .rejected(.staleTabGraph) = stale else {
            Issue.record("expected stale tab graph rejection")
            return
        }
    }

    @Test("stale active arrangement rejects without graph mutation")
    func staleActiveArrangementRejectsWithoutMutation() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let registry = AtomRegistry()
        registry.workspaceTabGraph.replaceTabStates([fixture.tabState])
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let splitID = fixture.tabState.arrangements[1].layout.dividerIds[0]
        let decision = WorkspaceLayoutResizeTransitionPlanner.plan(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: splitID,
                ratio: 0.4
            ),
            context: .selectedActiveArrangement(
                tab: fixture.tabState,
                arrangementID: fixture.customArrangementID
            )
        )
        guard case .changed(let transition) = decision else {
            Issue.record("expected resize transition")
            return
        }
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.defaultArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let applier = WorkspaceLayoutResizeTransitionApplier(
            workspaceTabGraphAtom: registry.workspaceTabGraph,
            workspaceArrangementCursorAtom: registry.workspaceArrangementCursor
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
        #expect(registry.workspaceTabGraph.tabState(fixture.tabState.tabId) == fixture.tabState)
    }
}
