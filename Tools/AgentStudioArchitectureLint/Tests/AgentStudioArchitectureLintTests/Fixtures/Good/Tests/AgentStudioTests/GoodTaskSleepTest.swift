import Foundation

struct GoodTaskSleepTest {
    private let taskSleepMention = "Task.sleep(nanoseconds: 1)"

    func commentAndStringMentionsAreAllowed() {
        // Task.sleep(nanoseconds: 1) is policy text here, not a call.
        _ = taskSleepMention
    }

    func eventWaiterIsAllowed(harness: EventHarness) async {
        await harness.waitForEventCount(atLeast: 1)
    }

    func injectedFakeClockIsAllowed(clock: TestPushClock) async throws {
        try await clock.sleep(for: .milliseconds(1))
        await clock.waitForPendingSleepCount()
    }
}

struct EventHarness {
    func waitForEventCount(atLeast count: Int) async {
        _ = count
    }
}

struct TestPushClock {
    func sleep(for duration: Duration) async throws {
        _ = duration
    }

    func waitForPendingSleepCount() async {}
}
