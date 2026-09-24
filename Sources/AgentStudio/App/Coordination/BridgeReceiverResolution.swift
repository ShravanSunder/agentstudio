import AgentStudioCore
import Foundation

/// Maps the pane a Bridge command addresses to its receiving Bridge, from the
/// durable pane graph rather than focus. A terminal is its own receiver and a
/// standalone Bridge pane is itself; a Zoom companion renders its terminal's
/// receiver; a drawer child maps to its owner's receiver and never has one of
/// its own. Other owner kinds have no receiver.
enum BridgeReceiverResolution {
    static func receiver(
        forCommandPaneId paneId: UUID,
        zoomSourcePaneIdByCompanionPaneId: [UUID: UUID],
        pane: (UUID) -> Pane?
    ) -> BridgeReceiver? {
        if let sourcePaneId = zoomSourcePaneIdByCompanionPaneId[paneId] {
            return .terminal(sourcePaneId)
        }
        guard let addressed = pane(paneId) else { return nil }
        let owner: Pane
        if let parentPaneId = addressed.parentPaneId {
            guard let parent = pane(parentPaneId) else { return nil }
            owner = parent
        } else {
            owner = addressed
        }
        switch owner.content {
        case .terminal:
            return .terminal(owner.id)
        case .bridgePanel:
            return .standalone(owner.id)
        default:
            return nil
        }
    }
}
