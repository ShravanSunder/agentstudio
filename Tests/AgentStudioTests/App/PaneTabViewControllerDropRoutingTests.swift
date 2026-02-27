import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneTabViewControllerDropRoutingTests")
struct PaneTabViewControllerDropRoutingTests {
    @Test
    func resolveDrawerMoveDropAction_returnsMoveAction_forSameDrawerParent() {
        let parentPaneId = UUID()
        let sourcePaneId = UUID()
        let destinationPaneId = UUID()

        var sourcePane = makePane(id: sourcePaneId)
        sourcePane.kind = .drawerChild(parentPaneId: parentPaneId)

        var destinationPane = makePane(id: destinationPaneId)
        destinationPane.kind = .drawerChild(parentPaneId: parentPaneId)

        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: UUID()))

        let action = PaneTabViewController.resolveDrawerMoveDropAction(
            payload: payload,
            destinationPane: destinationPane,
            sourcePane: sourcePane,
            zone: .left
        )

        #expect(
            action
                == .moveDrawerPane(
                    parentPaneId: parentPaneId,
                    drawerPaneId: sourcePaneId,
                    targetDrawerPaneId: destinationPaneId,
                    direction: .left
                )
        )
    }

    @Test
    func resolveDrawerMoveDropAction_returnsNil_forCrossParentMove() {
        let sourceParentPaneId = UUID()
        let destinationParentPaneId = UUID()
        let sourcePaneId = UUID()
        let destinationPaneId = UUID()

        var sourcePane = makePane(id: sourcePaneId)
        sourcePane.kind = .drawerChild(parentPaneId: sourceParentPaneId)

        var destinationPane = makePane(id: destinationPaneId)
        destinationPane.kind = .drawerChild(parentPaneId: destinationParentPaneId)

        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: UUID()))

        let action = PaneTabViewController.resolveDrawerMoveDropAction(
            payload: payload,
            destinationPane: destinationPane,
            sourcePane: sourcePane,
            zone: .right
        )

        #expect(action == nil)
    }

    @Test
    func resolveDrawerMoveDropAction_returnsNil_whenDestinationIsLayoutPane() {
        let sourcePaneId = UUID()
        let destinationPaneId = UUID()
        let parentPaneId = UUID()

        var sourcePane = makePane(id: sourcePaneId)
        sourcePane.kind = .drawerChild(parentPaneId: parentPaneId)
        let destinationPane = makePane(id: destinationPaneId)

        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: UUID()))

        let action = PaneTabViewController.resolveDrawerMoveDropAction(
            payload: payload,
            destinationPane: destinationPane,
            sourcePane: sourcePane,
            zone: .left
        )

        #expect(action == nil)
    }
}
