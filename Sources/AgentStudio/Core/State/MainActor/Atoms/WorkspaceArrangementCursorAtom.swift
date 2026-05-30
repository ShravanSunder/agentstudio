import Foundation
import Observation

struct ArrangementDrawerCursorKey: Hashable {
    let arrangementId: UUID
    let drawerId: UUID
}

struct ArrangementPaneCursorState: Equatable, Hashable {
    var activePaneId: UUID?
}

struct ArrangementDrawerCursorState: Equatable, Hashable {
    var activeChildId: UUID?
}

@MainActor
@Observable
final class WorkspaceArrangementCursorAtom {
    private(set) var activeArrangementIdsByTabId: [UUID: UUID] = [:]
    private(set) var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
    private(set) var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]

    func replaceStates(_ states: [TabArrangementState]) {
        var activeArrangementIdsByTabId: [UUID: UUID] = [:]
        var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
        var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]

        for state in states {
            activeArrangementIdsByTabId[state.tabId] = state.activeArrangementId
            for arrangement in state.arrangements {
                paneCursorsByArrangementId[arrangement.id] = ArrangementPaneCursorState(
                    activePaneId: arrangement.activePaneId
                )
                for (drawerId, drawerView) in arrangement.drawerViews {
                    drawerCursorsByKey[
                        ArrangementDrawerCursorKey(arrangementId: arrangement.id, drawerId: drawerId)
                    ] = ArrangementDrawerCursorState(activeChildId: drawerView.activeChildId)
                }
            }
        }

        self.activeArrangementIdsByTabId = activeArrangementIdsByTabId
        self.paneCursorsByArrangementId = paneCursorsByArrangementId
        self.drawerCursorsByKey = drawerCursorsByKey
    }

    func activeArrangementId(forTab tabId: UUID) -> UUID? {
        activeArrangementIdsByTabId[tabId]
    }

    func activePaneId(forArrangement arrangementId: UUID) -> UUID? {
        paneCursorsByArrangementId[arrangementId]?.activePaneId
    }

    func activeChildId(forArrangement arrangementId: UUID, drawerId: UUID) -> UUID? {
        drawerCursorsByKey[ArrangementDrawerCursorKey(arrangementId: arrangementId, drawerId: drawerId)]?.activeChildId
    }
}
