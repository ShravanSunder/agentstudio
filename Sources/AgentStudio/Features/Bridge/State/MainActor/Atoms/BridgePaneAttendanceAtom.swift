import AgentStudioInfrastructure
import Foundation
import Observation

package enum BridgePaneAttendanceEvent: String, CaseIterable, Sendable {
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
package final class BridgePaneAttendanceAtom {
    private(set) var ordinalByPaneId: [UUID: UInt64] = [:]
    @ObservationIgnored private let ordinalByPaneIdFamily = AtomFamily<UUID, UInt64>(
        telemetryLabel: "bridge_pane_attendance",
        isContentEqual: ==
    )
    @ObservationIgnored private let ordinalRevision = AtomRevision()
    private var nextOrdinal: UInt64 = 0

    package init() {}

    @discardableResult
    package func record(_ event: BridgePaneAttendanceEvent, for paneId: UUID) -> UInt64 {
        _ = event
        nextOrdinal += 1
        ordinalByPaneId[paneId] = nextOrdinal
        let mutation = AtomMutationContext(aggregateRevision: ordinalRevision)
        ordinalByPaneIdFamily.setValue(nextOrdinal, for: paneId, mutation: mutation)
        mutation.commit()
        return nextOrdinal
    }

    package func ordinal(for paneId: UUID) -> UInt64? {
        ordinalByPaneIdFamily.value(for: paneId)
    }

    package func remove(paneId: UUID) {
        ordinalByPaneId.removeValue(forKey: paneId)
        let mutation = AtomMutationContext(aggregateRevision: ordinalRevision)
        ordinalByPaneIdFamily.removeValue(for: paneId, mutation: mutation)
        mutation.commit()
    }

    package func ordinalSnapshot() -> [UUID: UInt64] {
        ordinalByPaneId
    }
}
