import AgentStudioCore
import Foundation
import Testing

actor RecordedEventBuffer<Envelope: Sendable> {
    private struct EventWaiter {
        let predicate: @Sendable (Envelope) -> Bool
        let continuation: CheckedContinuation<Envelope, Never>
    }

    private var events: [Envelope] = []
    private var eventWaiters: [EventWaiter] = []

    func append(_ event: Envelope) {
        events.append(event)

        var matchingWaiters: [EventWaiter] = []
        var pendingWaiters: [EventWaiter] = []
        for waiter in eventWaiters {
            if waiter.predicate(event) {
                matchingWaiters.append(waiter)
            } else {
                pendingWaiters.append(waiter)
            }
        }
        eventWaiters = pendingWaiters
        for waiter in matchingWaiters {
            waiter.continuation.resume(returning: event)
        }
    }

    func snapshot() -> [Envelope] {
        events
    }

    func count(where predicate: @Sendable (Envelope) -> Bool) -> Int {
        events.filter(predicate).count
    }

    func last(where predicate: @Sendable (Envelope) -> Bool) -> Envelope? {
        events.last(where: predicate)
    }

    func firstEvent(where predicate: @escaping @Sendable (Envelope) -> Bool) async -> Envelope {
        if let event = events.first(where: predicate) {
            return event
        }

        return await withCheckedContinuation { continuation in
            eventWaiters.append(EventWaiter(predicate: predicate, continuation: continuation))
        }
    }
}

package final class RecordingSubscriber<Envelope: Sendable>: @unchecked Sendable {
    private let buffer = RecordedEventBuffer<Envelope>()
    // Safe because the task reference is only assigned during init before the
    // subscriber is shared, and later only read/cancelled during shutdown.
    private var task: Task<Void, Never>?

    package init(stream: AsyncStream<Envelope>) {
        task = Task {
            for await event in stream {
                await self.buffer.append(event)
            }
        }
    }

    package init(stream: EventBusSubscription<Envelope>) {
        task = Task {
            for await event in stream {
                await self.buffer.append(event)
            }
        }
    }

    package init(subscription: EventBusSubscription<Envelope>) {
        task = Task {
            for await event in subscription {
                await self.buffer.append(event)
            }
        }
    }

    package func snapshot() async -> [Envelope] {
        await buffer.snapshot()
    }

    package func count(where predicate: @escaping @Sendable (Envelope) -> Bool) async -> Int {
        await buffer.count(where: predicate)
    }

    package func last(where predicate: @escaping @Sendable (Envelope) -> Bool) async -> Envelope? {
        await buffer.last(where: predicate)
    }

    package func firstEvent(where predicate: @escaping @Sendable (Envelope) -> Bool) async -> Envelope {
        await buffer.firstEvent(where: predicate)
    }

    package func shutdown() async {
        task?.cancel()
        if let task {
            await task.value
        }
    }
}

package struct EventBusHarness<Envelope: Sendable> {
    package let bus: EventBus<Envelope>

    package init(
        replayConfiguration: EventBus<Envelope>.ReplayConfiguration? = nil
    ) {
        bus = EventBus(replayConfiguration: replayConfiguration)
    }

    package func makeSubscriber(
        policy: BusSubscriberPolicy = .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
        subscriberName: String = "EventBusHarness"
    ) async -> RecordingSubscriber<Envelope> {
        let subscription = await bus.subscribe(policy: policy, subscriberName: subscriberName)
        return RecordingSubscriber(subscription: subscription)
    }

    @discardableResult
    package func post(_ envelope: Envelope) async -> EventBus<Envelope>.PostResult {
        await bus.post(envelope)
    }

    @discardableResult
    package func postAll(_ envelopes: [Envelope]) async -> [EventBus<Envelope>.PostResult] {
        var results: [EventBus<Envelope>.PostResult] = []
        results.reserveCapacity(envelopes.count)
        for envelope in envelopes {
            results.append(await bus.post(envelope))
        }
        return results
    }
}

/// Waits for `condition`, bounded primarily by wall-clock time rather than a MainActor yield
/// count. The fast lane runs many suites concurrently in one process, so unrelated suites'
/// MainActor jobs can consume this suite's yield turns; a fixed turn count is therefore not a
/// reliable timeout. `maxTurns` defaults to no cap at all; it only bounds the handful of call
/// sites that already pass an explicit value, as an additional limit layered on top of `timeout`.
package func assertEventuallyAsync(
    _ description: String,
    maxTurns: Int? = nil,
    timeout: Duration = .seconds(5),
    condition: @escaping @Sendable () async -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var turn = 0
    while clock.now < deadline, maxTurns.map({ turn < $0 }) ?? true {
        if await condition() {
            return
        }
        await Task.yield()
        turn += 1
    }

    #expect(await condition(), "\(description) timed out")
}

/// See `assertEventuallyAsync` above: the same wall-clock bound, for a `@MainActor` condition.
@MainActor
package func assertEventuallyMain(
    _ description: String,
    maxTurns: Int? = nil,
    timeout: Duration = .seconds(5),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var turn = 0
    while clock.now < deadline, maxTurns.map({ turn < $0 }) ?? true {
        if condition() {
            return
        }
        await Task.yield()
        turn += 1
    }

    #expect(condition(), "\(description) timed out")
}

package func waitForBusSubscriberCount<Envelope: Sendable>(
    _ bus: EventBus<Envelope>,
    atLeast expectedCount: Int,
    maxTurns: Int = 200
) async {
    await assertEventuallyAsync(
        "bus subscriber count should reach \(expectedCount)",
        maxTurns: maxTurns
    ) {
        await bus.subscriberCount >= expectedCount
    }
}

package func waitForBusSubscriberRegistration<Envelope: Sendable>(
    _ bus: EventBus<Envelope>,
    subscriberName: String
) async {
    await bus.waitForSubscriberRegistration(subscriberName: subscriberName)
}

package func assertBusDrained<Envelope: Sendable>(
    _ bus: EventBus<Envelope>,
    maxTurns: Int = 200
) async {
    await assertEventuallyAsync(
        "bus should have no subscribers",
        maxTurns: maxTurns
    ) {
        await bus.subscriberCount == 0
    }
}
