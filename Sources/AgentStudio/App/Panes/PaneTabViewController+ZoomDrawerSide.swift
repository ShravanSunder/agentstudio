import AgentStudioCore
import Foundation

extension AppCommand {
    /// Pane Zoom region a move-drawer command places the drawer over.
    var zoomDrawerTargetSide: DrawerZoomSide? {
        switch self {
        case .moveZoomDrawerToTerminal: .terminal
        case .moveZoomDrawerToBridge: .bridge
        default: nil
        }
    }

    /// The side command that moves a drawer away from its current region.
    static func moveZoomDrawerCommand(awayFrom effectiveSide: DrawerZoomSide) -> AppCommand {
        switch effectiveSide {
        case .terminal: .moveZoomDrawerToBridge
        case .bridge: .moveZoomDrawerToTerminal
        }
    }
}

extension PaneTabViewController {
    /// Zoom source of the active tab. Side commands target its drawer even
    /// when a drawer child or the Bridge companion holds focus.
    func activeZoomSourcePaneId() -> UUID? {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return nil }
        return store.panePresentationAtom.zoomPresentation(forTab: activeTabId)?.sourcePaneId
    }

    /// The owner must already have a drawer; the side command never creates
    /// one. Zoom-source authority is left to workspace validation.
    func zoomDrawerSideAction(side: DrawerZoomSide, ownerPaneId: UUID?) -> WorkspaceActionCommand? {
        guard let ownerPaneId, store.paneAtom.pane(ownerPaneId)?.drawer != nil else { return nil }
        return .setDrawerZoomSide(parentPaneId: ownerPaneId, side: side)
    }
}
