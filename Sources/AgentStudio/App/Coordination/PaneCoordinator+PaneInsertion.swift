import Foundation

struct PaneInsertionRequest {
    let paneId: UUID
    let tabId: UUID
    let targetPaneId: UUID
    let direction: Layout.SplitDirection
    let position: Layout.Position
    let sizingMode: DropSizingMode
    let failureContext: String
}

@MainActor
extension PaneCoordinator {
    func insertPaneIntoTab(_ request: PaneInsertionRequest) -> Bool {
        guard
            store.tabLayoutAtom.insertPane(
                request.paneId, inTab: request.tabId, at: request.targetPaneId,
                direction: request.direction, position: request.position, sizingMode: request.sizingMode)
        else {
            Self.logger.error(
                "\(request.failureContext): failed inserting pane \(request.paneId) into tab \(request.tabId)")
            return false
        }
        return true
    }
}
