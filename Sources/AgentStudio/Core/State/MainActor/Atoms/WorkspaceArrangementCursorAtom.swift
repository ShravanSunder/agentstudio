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
final class WorkspaceArrangementCursorAtom {
    private(set) var activeArrangementIdsByTabId: [UUID: UUID] = [:]
    private(set) var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
    private(set) var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
    func replaceCursors(
        activeArrangementIdsByTabId: [UUID: UUID],
        paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState],
        drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    ) {
        if self.activeArrangementIdsByTabId != activeArrangementIdsByTabId {
            self.activeArrangementIdsByTabId = activeArrangementIdsByTabId
        }
        if self.paneCursorsByArrangementId != paneCursorsByArrangementId {
            self.paneCursorsByArrangementId = paneCursorsByArrangementId
        }
        if self.drawerCursorsByKey != drawerCursorsByKey {
            self.drawerCursorsByKey = drawerCursorsByKey
        }
    }

    func activeArrangementId(forTab tabId: UUID) -> UUID? {
        activeArrangementIdsByTabId[tabId]
    }

    func hasActiveArrangementCursor(tabID: UUID) -> Bool {
        activeArrangementIdsByTabId[tabID] != nil
    }

    func activePaneId(forArrangement arrangementId: UUID) -> UUID? {
        paneCursorsByArrangementId[arrangementId]?.activePaneId
    }

    func hasPaneCursor(arrangementID: UUID) -> Bool {
        paneCursorsByArrangementId[arrangementID] != nil
    }

    func activeChildId(forArrangement arrangementId: UUID, drawerId: UUID) -> UUID? {
        drawerCursorsByKey[ArrangementDrawerCursorKey(arrangementId: arrangementId, drawerId: drawerId)]?.activeChildId
    }

    func hasDrawerCursor(_ key: ArrangementDrawerCursorKey) -> Bool {
        drawerCursorsByKey[key] != nil
    }

    func insertActiveArrangementId(_ arrangementId: UUID, forTab tabId: UUID) {
        precondition(
            activeArrangementIdsByTabId[tabId] == nil,
            "active arrangement cursor must be absent before insertion"
        )
        activeArrangementIdsByTabId[tabId] = arrangementId
    }

    func insertPaneCursor(_ state: ArrangementPaneCursorState, forArrangement arrangementId: UUID) {
        precondition(
            paneCursorsByArrangementId[arrangementId] == nil,
            "active pane cursor must be absent before insertion"
        )
        paneCursorsByArrangementId[arrangementId] = state
    }

    func insertDrawerCursor(
        _ state: ArrangementDrawerCursorState,
        for key: ArrangementDrawerCursorKey
    ) {
        precondition(
            drawerCursorsByKey[key] == nil,
            "active drawer cursor must be absent before insertion"
        )
        drawerCursorsByKey[key] = state
    }

    func setActiveArrangementId(_ arrangementId: UUID, forTab tabId: UUID) {
        guard activeArrangementIdsByTabId[tabId] != arrangementId else { return }
        activeArrangementIdsByTabId[tabId] = arrangementId
    }

    func setPaneCursor(
        _ state: ArrangementPaneCursorState,
        forArrangement arrangementId: UUID
    ) {
        guard paneCursorsByArrangementId[arrangementId] != state else { return }
        paneCursorsByArrangementId[arrangementId] = state
    }

}
