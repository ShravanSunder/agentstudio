import Foundation
import Observation

@MainActor
@Observable
final class WorkspacePanePresentationAtom {
    private(set) var zoomedPaneIdsByTabId: [UUID: UUID] = [:]

    func replaceStates(_ states: [TabArrangementState]) {
        zoomedPaneIdsByTabId = states.reduce(into: [:]) { result, state in
            if let zoomedPaneId = state.zoomedPaneId {
                result[state.tabId] = zoomedPaneId
            }
        }
    }

    func setZoomedPaneId(_ paneId: UUID?, forTab tabId: UUID) {
        zoomedPaneIdsByTabId[tabId] = paneId
    }

    func zoomedPaneId(forTab tabId: UUID) -> UUID? {
        zoomedPaneIdsByTabId[tabId]
    }
}
