import Foundation

struct GoodEventDrivenWaitTest {
    /// Awaits the specific element on the stream: the loop suspends on delivery,
    /// it does not re-read a condition.
    func awaitsFirstMatchingElement(stream: AsyncStream<Int>) async -> Int? {
        for await value in stream where value > 0 {
            return value
        }
        return nil
    }

    /// A continuation gate resumed by the event, not a poll.
    func awaitsCompletionGate(register: (@escaping @Sendable () -> Void) -> Void) async {
        await withCheckedContinuation { continuation in
            register { continuation.resume() }
        }
    }

    /// An ordinary loop over recorded values: no yield, no sleep, no clock read.
    func totalOfRecordedEvents(events: [Int]) -> Int {
        var total = 0
        for event in events {
            total += event
        }
        return total
    }
}
