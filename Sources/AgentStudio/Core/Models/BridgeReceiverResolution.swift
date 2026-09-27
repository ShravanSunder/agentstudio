import Foundation

/// Maps the pane a Bridge command addresses to its receiving Bridge, from the
/// durable pane graph rather than focus. A terminal is its own receiver and a
/// standalone Bridge pane is itself; a Zoom companion renders its terminal's
/// receiver; a drawer child maps to its owner's receiver and never has one of
/// its own. Other owner kinds have no receiver.
package enum BridgeReceiverResolution {
    package static func receiver(
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

    /// Resolve from copied write-owner facts. The caller captures these raw
    /// values on MainActor, then runs this projection off-main.
    package static func receiver(
        forCommandPaneId paneId: UUID,
        companionEntriesBySourceID: [UUID: ZoomCompanionMetadata],
        paneStatesByID: [UUID: PaneGraphState]
    ) -> BridgeReceiver? {
        if let sourcePaneID = companionEntriesBySourceID.first(where: {
            $0.value.companionPaneId == paneId
        })?.key {
            return .terminal(sourcePaneID)
        }
        guard let addressed = paneStatesByID[paneId] else { return nil }
        let owner: PaneGraphState
        if let parentPaneID = addressed.parentPaneId {
            guard let parent = paneStatesByID[parentPaneID] else { return nil }
            owner = parent
        } else {
            owner = addressed
        }
        switch owner.paneContent {
        case .terminal: return .terminal(owner.id)
        case .bridgePanel: return .standalone(owner.id)
        default: return nil
        }
    }
}
