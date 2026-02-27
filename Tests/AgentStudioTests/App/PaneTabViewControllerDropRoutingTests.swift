import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneTabViewControllerDropRoutingTests")
struct PaneTabViewControllerDropRoutingTests {
    @Test
    func resolveDrawerMoveDropAction_returnsMoveAction_forSameDrawerParent() {
        let parentPaneId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let destinationPaneId = UUIDv7.generate()

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
        let sourceParentPaneId = UUIDv7.generate()
        let destinationParentPaneId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let destinationPaneId = UUIDv7.generate()

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
        let sourcePaneId = UUIDv7.generate()
        let destinationPaneId = UUIDv7.generate()
        let parentPaneId = UUIDv7.generate()

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
