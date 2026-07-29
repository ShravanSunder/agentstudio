import Foundation
import Observation

package enum WorkspaceFocusOwner: Equatable, Sendable {
    case mainPane(paneId: UUID?)
    case emptyDrawer(parentPaneId: UUID)
    case drawerPane(parentPaneId: UUID, paneId: UUID)
}

@MainActor
@Observable
package final class WorkspaceFocusOwnerAtom {
    package private(set) var owner: WorkspaceFocusOwner = .mainPane(paneId: nil)

    package init() {}

    package func focusMainPane(_ paneId: UUID?) {
        owner = .mainPane(paneId: paneId)
    }

    package func focusEmptyDrawer(parentPaneId: UUID) {
        owner = .emptyDrawer(parentPaneId: parentPaneId)
    }

    package func focusDrawerPane(parentPaneId: UUID, paneId: UUID) {
        owner = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
    }
}
