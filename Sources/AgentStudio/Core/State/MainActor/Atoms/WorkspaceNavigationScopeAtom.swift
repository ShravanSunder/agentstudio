import Foundation
import Observation

enum WorkspaceNavigationScope: Equatable, Sendable {
    case mainPane(paneId: UUID?)
    case emptyDrawer(parentPaneId: UUID)
    case drawerPane(parentPaneId: UUID, paneId: UUID)
}

@MainActor
@Observable
final class WorkspaceNavigationScopeAtom {
    private(set) var scope: WorkspaceNavigationScope = .mainPane(paneId: nil)

    func focusMainPane(_ paneId: UUID?) {
        scope = .mainPane(paneId: paneId)
    }

    func focusEmptyDrawer(parentPaneId: UUID) {
        scope = .emptyDrawer(parentPaneId: parentPaneId)
    }

    func focusDrawerPane(parentPaneId: UUID, paneId: UUID) {
        scope = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
    }
}
