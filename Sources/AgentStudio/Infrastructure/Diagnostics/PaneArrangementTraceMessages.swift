import Foundation

package enum PaneArrangementTraceMessages {
    package static func crossTabPaneMove(
        paneId: UUID,
        sourceTabId: UUID,
        destTabId: UUID,
        sourceTabClosed: Bool
    ) -> String {
        "WorkspaceSurfaceCoordinator.movePaneAcrossTabs pane=\(paneId) sourceTab=\(sourceTabId) destTab=\(destTabId) sourceClosed=\(sourceTabClosed)"
    }
}
