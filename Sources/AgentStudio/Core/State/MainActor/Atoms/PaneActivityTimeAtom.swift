import AgentStudioInfrastructure
import Foundation
import Observation

/// Runtime-only publication of the clock's already admitted pane times.
@MainActor
@Observable
package final class PaneActivityTimeAtom {
    @ObservationIgnored private let timeFamily = AtomFamily<UUID, PaneActivityTime>(
        telemetryLabel: "pane_activity_time",
        isContentEqual: ==
    )
    @ObservationIgnored private let acceptedRevision = AtomRevision()

    package init() {}

    package func value(for paneId: UUID) -> PaneActivityTime? {
        timeFamily.value(for: paneId)
    }

    package func revision(for paneId: UUID) -> Int {
        timeFamily.revision(for: paneId)
    }

    package func snapshot() -> [UUID: PaneActivityTime] {
        timeFamily.snapshot()
    }

    package func apply(_ batch: [PaneActivityTimeMutation]) {
        let mutation = AtomMutationContext(aggregateRevision: acceptedRevision)
        for change in batch {
            switch change {
            case .set(let paneId, let time):
                timeFamily.setValue(time, for: paneId, mutation: mutation)
            case .remove(let paneId):
                timeFamily.removeValue(for: paneId, mutation: mutation)
            }
        }
        mutation.commit()
    }
}
