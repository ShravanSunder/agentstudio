import Foundation
import Observation

@MainActor
@Observable
final class WorkspacePanePresentationAtom {
    private(set) var zoomedPaneIdsByTabId: [UUID: UUID] = [:]

    func replaceStates(_ states: [TabArrangementState]) {
        let zoomedPaneIdsByTabId = states.reduce(into: [UUID: UUID]()) { result, state in
            if let zoomedPaneId = state.zoomedPaneId {
                result[state.tabId] = zoomedPaneId
            }
        }
        guard self.zoomedPaneIdsByTabId != zoomedPaneIdsByTabId else { return }
        self.zoomedPaneIdsByTabId = zoomedPaneIdsByTabId
    }

    func zoomedPaneId(forTab tabId: UUID) -> UUID? {
        zoomedPaneIdsByTabId[tabId]
    }
}
