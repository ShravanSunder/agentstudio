import Foundation

package enum PaneActivitySource: Sendable, Equatable {
    case terminal
    case hook
}

package struct PaneActivityOccurrence: Sendable, Equatable {
    package let paneId: UUID
    package let source: PaneActivitySource
    package let orderingInstant: ContinuousClock.Instant
    package let wallTime: Date

    package init(
        paneId: UUID,
        source: PaneActivitySource,
        orderingInstant: ContinuousClock.Instant,
        wallTime: Date
    ) {
        self.paneId = paneId
        self.source = source
        self.orderingInstant = orderingInstant
        self.wallTime = wallTime
    }

    package var activityTime: PaneActivityTime {
        PaneActivityTime(
            orderingInstant: orderingInstant,
            wallTime: wallTime,
            source: source
        )
    }
}

package struct PaneActivityTime: Sendable, Equatable {
    package let orderingInstant: ContinuousClock.Instant
    package let wallTime: Date
    package let source: PaneActivitySource

    package init(
        orderingInstant: ContinuousClock.Instant,
        wallTime: Date,
        source: PaneActivitySource
    ) {
        self.orderingInstant = orderingInstant
        self.wallTime = wallTime
        self.source = source
    }
}

package enum PaneActivityTimeMutation: Sendable, Equatable {
    case set(UUID, PaneActivityTime)
    case remove(UUID)
}
