import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace drawer cursor transition applier")
struct WorkspaceDrawerCursorTransitionApplierTests {
    @Test("applier applies exact expand collapse and switch replacements")
    func applierAppliesExactReplacements() throws {
        // Arrange
        let parentPaneID = UUIDv7.generate()
        let firstDrawerID = UUIDv7.generate()
        let secondDrawerID = UUIDv7.generate()
        let atom = WorkspaceDrawerCursorAtom()
        let applier = WorkspaceDrawerCursorTransitionApplier(workspaceDrawerCursorAtom: atom)

        // Act / Assert
        let firstParentState = makeDrawerCursorApplierParentState(
            parentPaneID: parentPaneID,
            drawerID: firstDrawerID
        )
        let secondParentState = makeDrawerCursorApplierParentState(
            parentPaneID: parentPaneID,
            drawerID: secondDrawerID
        )
        let expandTransition = try requireDrawerToggleTransition(
            parentPaneState: firstParentState,
            currentExpandedDrawerID: nil
        )
        let switchTransition = try requireDrawerToggleTransition(
            parentPaneState: secondParentState,
            currentExpandedDrawerID: firstDrawerID
        )
        let collapseTransition = try requireDrawerToggleTransition(
            parentPaneState: secondParentState,
            currentExpandedDrawerID: secondDrawerID
        )

        // Act / Assert
        #expect(applier.apply(expandTransition) == .applied)
        #expect(atom.expandedDrawerId == firstDrawerID)
        #expect(applier.apply(switchTransition) == .applied)
        #expect(atom.expandedDrawerId == secondDrawerID)
        #expect(applier.apply(collapseTransition) == .applied)
        #expect(atom.expandedDrawerId == nil)
    }

    @Test("applier rejects stale current cursor without mutation")
    func applierRejectsStaleCurrentCursor() throws {
        // Arrange
        let expectedDrawerID = UUIDv7.generate()
        let actualDrawerID = UUIDv7.generate()
        let atom = WorkspaceDrawerCursorAtom(expandedDrawerId: actualDrawerID)
        let applier = WorkspaceDrawerCursorTransitionApplier(workspaceDrawerCursorAtom: atom)
        let transition = try requireDrawerToggleTransition(
            parentPaneState: makeDrawerCursorApplierParentState(drawerID: expectedDrawerID),
            currentExpandedDrawerID: expectedDrawerID
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleCurrentCursor(
                        expected: .expanded(drawerID: expectedDrawerID),
                        actual: .expanded(drawerID: actualDrawerID)
                    )
                )
        )
        #expect(atom.expandedDrawerId == actualDrawerID)
    }
}

private func makeDrawerCursorApplierParentState(
    parentPaneID: UUID = UUIDv7.generate(),
    drawerID: UUID
) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: parentPaneID,
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Parent"),
            kind: .layout(
                drawer: Drawer(
                    drawerId: drawerID,
                    parentPaneId: parentPaneID
                )
            )
        )
    )
}

private func requireDrawerToggleTransition(
    parentPaneState: PaneGraphState,
    currentExpandedDrawerID: UUID?
) throws -> WorkspaceDrawerToggleTransition {
    let decision = WorkspaceDrawerToggleTransitionPlanner.plan(
        WorkspaceDrawerToggleRequest(parentPaneID: parentPaneState.id),
        currentPaneState: parentPaneState,
        currentExpandedDrawerID: currentExpandedDrawerID
    )
    guard case .changed(let transition) = decision else {
        Issue.record("expected planner-constructed drawer toggle transition")
        throw WorkspaceDrawerCursorTransitionApplierTestError.transitionRejected
    }
    return transition
}

private enum WorkspaceDrawerCursorTransitionApplierTestError: Error {
    case transitionRejected
}
