import Foundation

enum PaneArrangementTraceMessages {
    static func crossTabPaneMove(
        paneId: UUID,
        sourceTabId: UUID,
        destTabId: UUID,
        sourceTabClosed: Bool
    ) -> String {
        "WorkspaceSurfaceCoordinator.movePaneAcrossTabs pane=\(paneId) sourceTab=\(sourceTabId) destTab=\(destTabId) sourceClosed=\(sourceTabClosed)"
    }
}
