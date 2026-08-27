import AgentStudioInfrastructure
import Foundation
import Observation

/// A pane's most recent settled terminal output line, decoupled from inbox notification
/// suppression. `InboxPromoter` intentionally drops notification creation for small, attended,
/// pinned-to-bottom bursts to avoid spamming the inbox — but a pane's own sidebar row still needs
/// to show its latest real content regardless of that suppression. This fact is runtime-only
/// presentation state, not persisted; the inbox notification list remains the durable record.
package struct PaneActivityStatusFact: Equatable, Sendable {
    package let lastOutputLine: String
    package let observedAt: Date

    package init(lastOutputLine: String, observedAt: Date) {
        self.lastOutputLine = lastOutputLine
        self.observedAt = observedAt
    }
}

@MainActor
@Observable
package final class PaneActivityStatusAtom {
    // Compares only `lastOutputLine`, not `observedAt`: a repeated identical line must stay a
    // no-op (no revision bump, no row wake) even though its observation timestamp always differs.
    // This is a second suppression layer on top of the projector's own unchanged-line suppression.
    @ObservationIgnored private let statusFamily = AtomFamily<UUID, PaneActivityStatusFact>(
        telemetryLabel: "pane_activity_status",
        isContentEqual: { $0.lastOutputLine == $1.lastOutputLine }
    )
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()
    @ObservationIgnored private var lastPublishedAtByPaneId: [UUID: Date] = [:]
    @ObservationIgnored private let minimumPublishInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date

    package init(
        minimumPublishInterval: Duration = AppPolicies.InboxNotification.paneActivityStatusMinimumPublishInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.minimumPublishInterval = Self.seconds(from: minimumPublishInterval)
        self.now = now
    }

    package func status(for paneId: UUID) -> PaneActivityStatusFact? {
        statusFamily.value(for: paneId)
    }

    /// Publishes `lastOutputLine` for `paneId` at every settled terminal activity outcome,
    /// regardless of whether `InboxPromoter` suppresses the corresponding notification. Subject to
    /// a timerless leading-edge rate limit: a settle within `minimumPublishInterval` of the pane's
    /// last published fact is dropped, not deferred. `AtomFamily`'s own equal-value suppression
    /// additionally no-ops an unchanged line for the same pane.
    @discardableResult
    package func recordSettledActivity(paneId: UUID, lastOutputLine: String?) -> Bool {
        guard let lastOutputLine, !lastOutputLine.isEmpty else { return false }
        guard statusFamily.value(for: paneId)?.lastOutputLine != lastOutputLine else {
            // Identical to the pane's current fact: not a rate-limit-consuming event, so a
            // same-line settle can never delay a later, genuinely different line.
            return false
        }
        let observedAt = now()
        if let lastPublishedAt = lastPublishedAtByPaneId[paneId],
            observedAt.timeIntervalSince(lastPublishedAt) < minimumPublishInterval
        {
            return false
        }
        lastPublishedAtByPaneId[paneId] = observedAt
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        statusFamily.setValue(
            PaneActivityStatusFact(lastOutputLine: lastOutputLine, observedAt: observedAt),
            for: paneId,
            mutation: mutation
        )
        mutation.commit()
        return true
    }

    package func clear(paneId: UUID) {
        lastPublishedAtByPaneId.removeValue(forKey: paneId)
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        statusFamily.removeValue(for: paneId, mutation: mutation)
        mutation.commit()
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let attosecondsPerSecond: Double = 1_000_000_000_000_000_000
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / attosecondsPerSecond
    }
}
