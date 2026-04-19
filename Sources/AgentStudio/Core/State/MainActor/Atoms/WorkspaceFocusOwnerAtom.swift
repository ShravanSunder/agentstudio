import Foundation
import Observation

enum WorkspaceFocusOwner: Equatable, Sendable {
    case mainPane(paneId: UUID?)
    case emptyDrawer(parentPaneId: UUID)
    case drawerPane(parentPaneId: UUID, paneId: UUID)
}

@MainActor
@Observable
final class WorkspaceFocusOwnerAtom {
    private(set) var owner: WorkspaceFocusOwner = .mainPane(paneId: nil)

    func focusMainPane(_ paneId: UUID?) {
        owner = .mainPane(paneId: paneId)
    }

    func focusEmptyDrawer(parentPaneId: UUID) {
        owner = .emptyDrawer(parentPaneId: parentPaneId)
    }

    func focusDrawerPane(parentPaneId: UUID, paneId: UUID) {
        owner = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
    }
}
