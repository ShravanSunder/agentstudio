import Foundation
import os

private let paneEventBusLogger = Logger(subsystem: "com.agentstudio", category: "PaneEventBus")

/// Typed async fan-out bus.
///
/// Producers `await post(_:)` and consumers iterate `for await` over independent streams
/// returned by `subscribe()`.
actor EventBus<Envelope: Sendable> {
    private var subscribers: [UUID: AsyncStream<Envelope>.Continuation] = [:]

    func subscribe(
        bufferingPolicy: AsyncStream<Envelope>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Envelope> {
        let subscriberID = UUID()
        let stream = AsyncStream<Envelope>(bufferingPolicy: bufferingPolicy) { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(subscriberID) }
            }
            self.subscribers[subscriberID] = continuation
        }
        return stream
    }

    func post(_ envelope: Envelope) {
        var droppedCount = 0
        var terminatedSubscriberIds: [UUID] = []

        for (subscriberId, continuation) in subscribers {
            switch continuation.yield(envelope) {
            case .enqueued:
                continue
            case .dropped:
                droppedCount += 1
            case .terminated:
                terminatedSubscriberIds.append(subscriberId)
            @unknown default:
                continue
            }
        }

        if droppedCount > 0 {
            paneEventBusLogger.warning(
                "Dropped pane event for \(droppedCount, privacy: .public) subscriber(s) due to buffering policy overflow"
            )
        }

        for subscriberId in terminatedSubscriberIds {
            subscribers.removeValue(forKey: subscriberId)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
