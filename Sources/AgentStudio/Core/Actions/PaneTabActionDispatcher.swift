import Foundation

@MainActor
final class PaneTabActionDispatcher: PaneActionDispatching {
    private let dispatchClosure: (PaneActionCommand) -> Void
    private let shouldHandleSplitDragPayloadClosure: (SplitDropPayload) -> Bool
    private let shouldAcceptDropClosure: (SplitDropPayload, UUID, DropZoneSide) -> Bool
    private let handleDropClosure: (SplitDropPayload, UUID, DropZoneSide, DropSizingMode) -> Void

    init(
        dispatch: @escaping (PaneActionCommand) -> Void,
        shouldHandleSplitDragPayload: @escaping (SplitDropPayload) -> Bool = { _ in true },
        shouldAcceptDrop: @escaping (SplitDropPayload, UUID, DropZoneSide) -> Bool,
        handleDrop: @escaping (SplitDropPayload, UUID, DropZoneSide, DropSizingMode) -> Void
    ) {
        self.dispatchClosure = dispatch
        self.shouldHandleSplitDragPayloadClosure = shouldHandleSplitDragPayload
        self.shouldAcceptDropClosure = shouldAcceptDrop
        self.handleDropClosure = handleDrop
    }

    func dispatch(_ action: PaneActionCommand) {
        if Thread.isMainThread == false {
            RestoreTrace.log("PaneTabActionDispatcher.dispatch offMainThread action=\(String(describing: action))")
        }
        dispatchClosure(action)
    }

    func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        shouldHandleSplitDragPayloadClosure(payload)
    }

    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide
    ) -> Bool {
        let result = shouldAcceptDropClosure(payload, destinationPaneId, zone)
        return result
    }

    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) {
        handleDropClosure(payload, destinationPaneId, zone, sizingMode)
    }
}
