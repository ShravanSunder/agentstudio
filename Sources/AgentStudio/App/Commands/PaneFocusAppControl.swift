import Foundation

enum PaneFocusAppControlError: Error, Equatable, Sendable {
    case targetNotFound
    case validationRejected
}

@MainActor
protocol PaneFocusAppControlling: Sendable {
    func focusPane(_ paneId: UUID) throws
}

@MainActor
final class PaneTabViewControllerPaneFocusAppControl: PaneFocusAppControlling, @unchecked Sendable {
    private let paneTabViewController: PaneTabViewController
    private let workspaceStore: WorkspaceStore

    init(paneTabViewController: PaneTabViewController, workspaceStore: WorkspaceStore) {
        self.paneTabViewController = paneTabViewController
        self.workspaceStore = workspaceStore
    }

    func focusPane(_ paneId: UUID) throws {
        let snapshot = workspaceStore.programmaticControlSnapshot()
        guard let pane = snapshot.panes.first(where: { $0.id == paneId }) else {
            throw PaneFocusAppControlError.targetNotFound
        }
        guard pane.tabId != nil else {
            throw PaneFocusAppControlError.validationRejected
        }

        paneTabViewController.execute(.focusPane, target: paneId, targetType: .pane)
    }
}
