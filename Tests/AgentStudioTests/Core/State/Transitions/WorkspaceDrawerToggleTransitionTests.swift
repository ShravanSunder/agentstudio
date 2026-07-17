import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace drawer toggle transitions")
struct WorkspaceDrawerToggleTransitionTests {
    @Test("planner emits exact expand collapse and switch transitions without mutating input")
    func plannerEmitsExactTransitionsWithoutMutatingInput() throws {
        // Arrange
        let parentPaneState = makeDrawerToggleParentPaneState()
        let originalParentPaneState = parentPaneState
        let parentPaneID = parentPaneState.id
        let drawerID = try #require(parentPaneState.drawer?.drawerId)
        let otherDrawerID = UUIDv7.generate()
        let request = WorkspaceDrawerToggleRequest(parentPaneID: parentPaneID)

        // Act
        let expandDecision = WorkspaceDrawerToggleTransitionPlanner.plan(
            request,
            currentPaneState: parentPaneState,
            currentExpandedDrawerID: nil
        )
        let collapseDecision = WorkspaceDrawerToggleTransitionPlanner.plan(
            request,
            currentPaneState: parentPaneState,
            currentExpandedDrawerID: drawerID
        )
        let switchDecision = WorkspaceDrawerToggleTransitionPlanner.plan(
            request,
            currentPaneState: parentPaneState,
            currentExpandedDrawerID: otherDrawerID
        )

        // Assert
        guard case .changed(let expandTransition) = expandDecision,
            case .changed(let collapseTransition) = collapseDecision,
            case .changed(let switchTransition) = switchDecision
        else {
            Issue.record("expected changed drawer toggle transitions")
            return
        }
        #expect(expandTransition.parentPaneID == parentPaneID)
        #expect(expandTransition.operation == .expand(drawerID: drawerID))
        #expect(expandTransition.expectedCursor == .collapsed)
        #expect(expandTransition.replacementCursor == .expanded(drawerID: drawerID))
        #expect(collapseTransition.parentPaneID == parentPaneID)
        #expect(collapseTransition.operation == .collapse(drawerID: drawerID))
        #expect(collapseTransition.expectedCursor == .expanded(drawerID: drawerID))
        #expect(collapseTransition.replacementCursor == .collapsed)
        #expect(switchTransition.parentPaneID == parentPaneID)
        #expect(
            switchTransition.operation
                == .switchExpandedDrawer(
                    fromDrawerID: otherDrawerID,
                    toDrawerID: drawerID
                )
        )
        #expect(switchTransition.expectedCursor == .expanded(drawerID: otherDrawerID))
        #expect(switchTransition.replacementCursor == .expanded(drawerID: drawerID))
        #expect(parentPaneState == originalParentPaneState)
    }

    @Test("planner rejects missing mismatched drawer-child and invalid drawer ownership")
    func plannerRejectsInvalidParentState() {
        // Arrange
        let requestedPaneID = UUIDv7.generate()
        let mismatchedPaneState = makeDrawerToggleParentPaneState()
        let drawerChildState = PaneGraphState(
            pane: Pane(
                id: requestedPaneID,
                content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
                metadata: PaneMetadata(title: "Drawer child"),
                kind: .drawerChild(parentPaneId: UUIDv7.generate())
            )
        )
        let wrongDrawerParentID = UUIDv7.generate()
        let wrongDrawerID = UUIDv7.generate()
        let invalidOwnershipState = makeDrawerToggleParentPaneState(
            parentPaneID: requestedPaneID,
            drawerID: wrongDrawerID,
            drawerParentPaneID: wrongDrawerParentID
        )
        let request = WorkspaceDrawerToggleRequest(parentPaneID: requestedPaneID)

        // Act / Assert
        #expect(
            WorkspaceDrawerToggleTransitionPlanner.plan(
                request,
                currentPaneState: nil,
                currentExpandedDrawerID: nil
            ) == .rejected(.parentPaneMissing(requestedPaneID))
        )
        #expect(
            WorkspaceDrawerToggleTransitionPlanner.plan(
                request,
                currentPaneState: mismatchedPaneState,
                currentExpandedDrawerID: nil
            )
                == .rejected(
                    .paneIdentityMismatch(
                        requestedPaneID: requestedPaneID,
                        currentPaneID: mismatchedPaneState.id
                    )
                )
        )
        #expect(
            WorkspaceDrawerToggleTransitionPlanner.plan(
                request,
                currentPaneState: drawerChildState,
                currentExpandedDrawerID: nil
            ) == .rejected(.paneHasNoDrawer(requestedPaneID))
        )
        #expect(
            WorkspaceDrawerToggleTransitionPlanner.plan(
                request,
                currentPaneState: invalidOwnershipState,
                currentExpandedDrawerID: nil
            )
                == .rejected(
                    .drawerParentMismatch(
                        drawerID: wrongDrawerID,
                        expectedParentPaneID: requestedPaneID,
                        actualParentPaneID: wrongDrawerParentID
                    )
                )
        )
    }
}

private func makeDrawerToggleParentPaneState(
    parentPaneID: UUID = UUIDv7.generate(),
    drawerID: UUID = UUIDv7.generate(),
    drawerParentPaneID: UUID? = nil
) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: parentPaneID,
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Parent"),
            kind: .layout(
                drawer: Drawer(
                    drawerId: drawerID,
                    parentPaneId: drawerParentPaneID ?? parentPaneID
                )
            )
        )
    )
}
