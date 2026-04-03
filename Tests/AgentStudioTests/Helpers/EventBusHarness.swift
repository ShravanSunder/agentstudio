import Foundation
import Testing

@testable import AgentStudio

actor RecordedEventBuffer<Envelope: Sendable> {
    private var events: [Envelope] = []

    func append(_ event: Envelope) {
        events.append(event)
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
}

final class RecordingSubscriber<Envelope: Sendable>: @unchecked Sendable {
    private let buffer = RecordedEventBuffer<Envelope>()
    // Safe because the task reference is only assigned during init before the
    // subscriber is shared, and later only read/cancelled during shutdown.
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<Envelope>) {
        task = Task {
            for await event in stream {
                await self.buffer.append(event)
            }
        }
    }

    func snapshot() async -> [Envelope] {
        await buffer.snapshot()
    }

    func count(where predicate: @escaping @Sendable (Envelope) -> Bool) async -> Int {
        await buffer.count(where: predicate)
    }

    func last(where predicate: @escaping @Sendable (Envelope) -> Bool) async -> Envelope? {
        await buffer.last(where: predicate)
    }

    func shutdown() async {
        task?.cancel()
        if let task {
            await task.value
        }
    }
}

struct EventBusHarness<Envelope: Sendable> {
    let bus: EventBus<Envelope>

    init(
        replayConfiguration: EventBus<Envelope>.ReplayConfiguration? = nil
    ) {
        bus = EventBus(replayConfiguration: replayConfiguration)
    }

    func makeSubscriber(
        bufferingPolicy: AsyncStream<Envelope>.Continuation.BufferingPolicy = .bufferingNewest(256)
    ) async -> RecordingSubscriber<Envelope> {
        let stream = await bus.subscribe(bufferingPolicy: bufferingPolicy)
        return RecordingSubscriber(stream: stream)
    }

    @discardableResult
    func post(_ envelope: Envelope) async -> EventBus<Envelope>.PostResult {
        await bus.post(envelope)
    }

    @discardableResult
    func postAll(_ envelopes: [Envelope]) async -> [EventBus<Envelope>.PostResult] {
        var results: [EventBus<Envelope>.PostResult] = []
        results.reserveCapacity(envelopes.count)
        for envelope in envelopes {
            results.append(await bus.post(envelope))
        }
        return results
    }
}

func assertEventuallyAsync(
    _ description: String,
    maxTurns: Int = 200,
    condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<maxTurns {
        if await condition() {
            return
        }
        await Task.yield()
    }

    #expect(await condition(), "\(description) timed out")
}

@MainActor
func assertEventuallyMain(
    _ description: String,
    maxTurns: Int = 200,
    condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<maxTurns {
        if condition() {
            return
        }
        await Task.yield()
    }

    #expect(condition(), "\(description) timed out")
}

func waitForBusSubscriberCount<Envelope: Sendable>(
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

func assertBusDrained<Envelope: Sendable>(
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
