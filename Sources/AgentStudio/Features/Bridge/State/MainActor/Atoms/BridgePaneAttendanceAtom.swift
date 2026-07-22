import Foundation
import Observation

enum BridgePaneAttendanceEvent: String, CaseIterable, Sendable {
    case tabActivation
    case paneFocus
    case defaultJump
    case newTabCreation
}

/// Runtime-only recency facts for deterministic Bridge command reuse.
///
/// Activity and attendance are intentionally distinct: visibility and refresh
/// may change native work admission, but only successful user-directed
/// attendance records advance this ordinal.
@MainActor
@Observable
final class BridgePaneAttendanceAtom {
    private(set) var ordinalByPaneId: [UUID: UInt64] = [:]
    private var nextOrdinal: UInt64 = 0

    @discardableResult
    func record(_ event: BridgePaneAttendanceEvent, for paneId: UUID) -> UInt64 {
        _ = event
        nextOrdinal += 1
        ordinalByPaneId[paneId] = nextOrdinal
        return nextOrdinal
    }

    func ordinal(for paneId: UUID) -> UInt64? {
        ordinalByPaneId[paneId]
    }

    func remove(paneId: UUID) {
        ordinalByPaneId.removeValue(forKey: paneId)
    }
}
