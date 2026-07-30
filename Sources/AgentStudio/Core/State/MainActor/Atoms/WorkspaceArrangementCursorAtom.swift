import AgentStudioInfrastructure
import Foundation
import Observation

struct ArrangementDrawerCursorKey: Hashable, Sendable {
    let arrangementId: UUID
    let drawerId: UUID
}

struct ArrangementPaneCursorState: Equatable, Hashable, Sendable {
    var activePaneId: UUID?
}

struct ArrangementDrawerCursorState: Equatable, Hashable, Sendable {
    var activeChildId: UUID?
}

@MainActor
@Observable
package final class WorkspaceArrangementCursorAtom {
    @ObservationIgnored private let activeArrangementRevisionCounter = AtomRevision()
    @ObservationIgnored private let activePaneRevisionCounter = AtomRevision()
    @ObservationIgnored private let drawerChildRevisionCounter = AtomRevision()
    private(set) var activeArrangementIdsByTabId: [UUID: UUID] = [:]
    private(set) var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
    private(set) var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]

    package var activeArrangementRevision: Int {
        activeArrangementRevisionCounter.value
    }

    package var activePaneRevision: Int {
        activePaneRevisionCounter.value
    }

    package var drawerChildRevision: Int {
        drawerChildRevisionCounter.value
    }

    func replaceCursors(
        activeArrangementIdsByTabId: [UUID: UUID],
        paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState],
        drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    ) {
        if self.activeArrangementIdsByTabId != activeArrangementIdsByTabId {
            self.activeArrangementIdsByTabId = activeArrangementIdsByTabId
            activeArrangementRevisionCounter.bump()
        }
        if self.paneCursorsByArrangementId != paneCursorsByArrangementId {
            self.paneCursorsByArrangementId = paneCursorsByArrangementId
            activePaneRevisionCounter.bump()
        }
        if self.drawerCursorsByKey != drawerCursorsByKey {
            self.drawerCursorsByKey = drawerCursorsByKey
            drawerChildRevisionCounter.bump()
        }
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
