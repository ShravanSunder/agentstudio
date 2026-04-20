import Foundation

@MainActor
protocol PaneActionDispatching: AnyObject {
    func dispatch(_ action: PaneActionCommand)
    func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool
    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    ) -> Bool
    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    )
}

extension PaneActionDispatching {
    func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        true
    }
}
