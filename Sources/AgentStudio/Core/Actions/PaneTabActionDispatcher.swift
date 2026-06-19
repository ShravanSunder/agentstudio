import Foundation

@MainActor
final class PaneTabActionDispatcher: PaneActionDispatching {
    private let dispatchClosure: (WorkspaceActionCommand) -> Void
    private let shouldHandleSplitDragPayloadClosure: (SplitDropPayload) -> Bool
    private let shouldAcceptDropClosure: (SplitDropPayload, UUID, DropZoneSide, DropSizingMode) -> Bool
    private let handleDropClosure: (SplitDropPayload, UUID, DropZoneSide, DropSizingMode) -> Void

    init(
        dispatch: @escaping (WorkspaceActionCommand) -> Void,
        shouldHandleSplitDragPayload: @escaping (SplitDropPayload) -> Bool,
        shouldAcceptDrop: @escaping (SplitDropPayload, UUID, DropZoneSide, DropSizingMode) -> Bool,
        handleDrop: @escaping (SplitDropPayload, UUID, DropZoneSide, DropSizingMode) -> Void
    ) {
        self.dispatchClosure = dispatch
        self.shouldHandleSplitDragPayloadClosure = shouldHandleSplitDragPayload
        self.shouldAcceptDropClosure = shouldAcceptDrop
        self.handleDropClosure = handleDrop
    }

    func dispatch(_ action: WorkspaceActionCommand) {
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
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) -> Bool {
        let result = shouldAcceptDropClosure(payload, destinationPaneId, zone, sizingMode)
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
