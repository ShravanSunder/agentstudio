import Foundation

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
        for continuation in subscribers.values {
            continuation.yield(envelope)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
