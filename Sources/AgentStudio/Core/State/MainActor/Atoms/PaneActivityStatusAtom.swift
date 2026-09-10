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
    package enum PublicationOutcome: Equatable, Sendable {
        case ignoredInput
        case equal
        case published
        case deferred
        case replaced
        case deadlineFired
        case cleared
    }

    // Compares only `lastOutputLine`, not `observedAt`: a repeated identical line must stay a
    // no-op (no revision bump, no row wake) even though its observation timestamp always differs.
    // This is a second suppression layer on top of the projector's own unchanged-line suppression.
    @ObservationIgnored private let statusFamily = AtomFamily<UUID, PaneActivityStatusFact>(
        telemetryLabel: "pane_activity_status",
        isContentEqual: { $0.lastOutputLine == $1.lastOutputLine }
    )
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()
    @ObservationIgnored private var lastPublishedAtByPaneId: [UUID: Duration] = [:]
    @ObservationIgnored private var pendingStatusByPaneId: [UUID: PendingStatus] = [:]
    @ObservationIgnored private let minimumPublishInterval: Duration
    @ObservationIgnored private let delay: AsyncDelay
    @ObservationIgnored private let wallNow: () -> Date
    @ObservationIgnored private let monotonicNow: () -> Duration
    @ObservationIgnored private let onPublicationOutcome: @MainActor @Sendable (PublicationOutcome) -> Void
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledDeadline: Duration?

    private struct PendingStatus {
        let fact: PaneActivityStatusFact
        let eligibleAt: Duration
    }

    package init(
        minimumPublishInterval: Duration = AppPolicies.InboxNotification.paneActivityStatusMinimumPublishInterval,
        clock: (any Clock<Duration> & Sendable)? = nil,
        now: @escaping () -> Date = Date.init,
        monotonicNow: @escaping () -> Duration = {
            .nanoseconds(Int64(clamping: DispatchTime.now().uptimeNanoseconds))
        },
        onPublicationOutcome: @escaping @MainActor @Sendable (PublicationOutcome) -> Void = { _ in }
    ) {
        self.minimumPublishInterval = minimumPublishInterval
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        wallNow = now
        self.monotonicNow = monotonicNow
        self.onPublicationOutcome = onPublicationOutcome
    }

    isolated deinit {
        deadlineTask?.cancel()
    }

    package func status(for paneId: UUID) -> PaneActivityStatusFact? {
        statusFamily.value(for: paneId)
    }

    /// Publishes `lastOutputLine` for `paneId` at every settled terminal activity outcome,
    /// regardless of whether `InboxPromoter` suppresses the corresponding notification. Subject to
    /// a latest-value deferral gate: a settle within `minimumPublishInterval` of the pane's last
    /// published fact replaces that pane's one pending value and publishes at the eligibility
    /// deadline without requiring another settle. `AtomFamily`'s own equal-value suppression
    /// additionally no-ops an unchanged line for the same pane.
    @discardableResult
    package func recordSettledActivity(paneId: UUID, lastOutputLine: String?) -> Bool {
        guard let lastOutputLine, !lastOutputLine.isEmpty else {
            onPublicationOutcome(.ignoredInput)
            return false
        }
        if pendingStatusByPaneId[paneId]?.fact.lastOutputLine == lastOutputLine {
            onPublicationOutcome(.equal)
            return false
        }
        if statusFamily.value(for: paneId)?.lastOutputLine == lastOutputLine {
            pendingStatusByPaneId.removeValue(forKey: paneId)
            rescheduleDeadlineTask()
            onPublicationOutcome(.equal)
            return false
        }
        let observedAt = wallNow()
        let admittedAt = monotonicNow()
        if let lastPublishedAt = lastPublishedAtByPaneId[paneId],
            admittedAt < lastPublishedAt + minimumPublishInterval
        {
            let didReplacePending = pendingStatusByPaneId[paneId] != nil
            pendingStatusByPaneId[paneId] = PendingStatus(
                fact: PaneActivityStatusFact(lastOutputLine: lastOutputLine, observedAt: observedAt),
                eligibleAt: lastPublishedAt + minimumPublishInterval
            )
            rescheduleDeadlineTask()
            onPublicationOutcome(didReplacePending ? .replaced : .deferred)
            return false
        }
        pendingStatusByPaneId.removeValue(forKey: paneId)
        publish(
            PaneActivityStatusFact(lastOutputLine: lastOutputLine, observedAt: observedAt),
            for: paneId,
            publishedAt: admittedAt
        )
        rescheduleDeadlineTask()
        onPublicationOutcome(.published)
        return true
    }

    package func clear(paneId: UUID) {
        lastPublishedAtByPaneId.removeValue(forKey: paneId)
        pendingStatusByPaneId.removeValue(forKey: paneId)
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        statusFamily.removeValue(for: paneId, mutation: mutation)
        mutation.commit()
        rescheduleDeadlineTask()
        onPublicationOutcome(.cleared)
    }

    private func publish(
        _ fact: PaneActivityStatusFact,
        for paneId: UUID,
        publishedAt: Duration
    ) {
        lastPublishedAtByPaneId[paneId] = publishedAt
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        statusFamily.setValue(fact, for: paneId, mutation: mutation)
        mutation.commit()
    }

    private func rescheduleDeadlineTask() {
        let nextDeadline = pendingStatusByPaneId.values.map(\.eligibleAt).min()
        guard nextDeadline != scheduledDeadline else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadline = nextDeadline
        guard let nextDeadline else { return }

        let waitDuration = max(.zero, nextDeadline - monotonicNow())
        let delay = self.delay
        deadlineTask = Task { @MainActor [weak self] in
            do {
                try await delay.wait(waitDuration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, scheduledDeadline == nextDeadline else { return }
            deadlineTask = nil
            scheduledDeadline = nil
            publishEligiblePendingStatuses(at: monotonicNow())
            rescheduleDeadlineTask()
        }
    }

    private func publishEligiblePendingStatuses(at currentInstant: Duration) {
        let eligiblePaneIds = pendingStatusByPaneId.compactMap { paneId, pendingStatus in
            pendingStatus.eligibleAt <= currentInstant ? paneId : nil
        }
        for paneId in eligiblePaneIds {
            guard let pendingStatus = pendingStatusByPaneId.removeValue(forKey: paneId) else { continue }
            guard statusFamily.value(for: paneId)?.lastOutputLine != pendingStatus.fact.lastOutputLine else {
                continue
            }
            publish(pendingStatus.fact, for: paneId, publishedAt: currentInstant)
            onPublicationOutcome(.deadlineFired)
        }
    }
}
