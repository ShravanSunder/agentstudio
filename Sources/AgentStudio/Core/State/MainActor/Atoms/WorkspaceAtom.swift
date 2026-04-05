import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceAtom {
    private(set) var panes: [UUID: Pane] = [:]

    func addPane(_ pane: Pane) {
        panes[pane.id] = pane
    }

    func pane(_ id: UUID) -> Pane? {
        panes[id]
    }

    func renamePane(_ paneId: UUID, title: String) {
        guard panes[paneId] != nil else { return }
        panes[paneId]!.metadata.updateTitle(title)
    }
}
