import Foundation

@MainActor
final class PaneTabActionDispatcher: PaneActionDispatching {
    private let dispatchClosure: (PaneActionCommand) -> Void
    private let shouldAcceptDropClosure: (SplitDropPayload, UUID, DropZone) -> Bool
    private let handleDropClosure: (SplitDropPayload, UUID, DropZone) -> Void

    init(
        dispatch: @escaping (PaneActionCommand) -> Void,
        shouldAcceptDrop: @escaping (SplitDropPayload, UUID, DropZone) -> Bool,
        handleDrop: @escaping (SplitDropPayload, UUID, DropZone) -> Void
    ) {
        self.dispatchClosure = dispatch
        self.shouldAcceptDropClosure = shouldAcceptDrop
        self.handleDropClosure = handleDrop
    }

    func dispatch(_ action: PaneActionCommand) {
        if Thread.isMainThread == false {
            RestoreTrace.log("PaneTabActionDispatcher.dispatch offMainThread action=\(String(describing: action))")
        }
        dispatchClosure(action)
    }

    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    ) -> Bool {
        let result = shouldAcceptDropClosure(payload, destinationPaneId, zone)
        return result
    }

    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    ) {
        handleDropClosure(payload, destinationPaneId, zone)
    }
}
