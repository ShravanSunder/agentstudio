import Testing

@testable import AgentStudioTestSupport

@Suite("Test push clock")
struct TestPushClockTests {
    @Test("advancing the next sleep atomically resumes only the earliest deadline")
    func advanceToNextPendingSleepResumesEarliestDeadline() async throws {
        let clock = TestPushClock()
        let start = clock.now
        let earlierTask = Task {
            try await clock.sleep(until: start.advanced(by: .seconds(1)))
        }
        let laterTask = Task {
            try await clock.sleep(until: start.advanced(by: .seconds(2)))
        }
        await clock.waitForPendingSleepCount(exactly: 2)

        #expect(clock.advanceToNextPendingSleep())
        try await earlierTask.value
        #expect(clock.pendingSleepCount == 1)
        #expect(clock.now == start.advanced(by: .seconds(1)))

        #expect(clock.advanceToNextPendingSleep())
        try await laterTask.value
        #expect(clock.pendingSleepCount == 0)
        #expect(clock.now == start.advanced(by: .seconds(2)))
        #expect(!clock.advanceToNextPendingSleep())
    }

    @Test("sleep entered after task cancellation terminates immediately")
    func cancelledBeforeSleepRegistrationTerminatesImmediately() async {
        let clock = TestPushClock()
        let sleepTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            try await clock.sleep(until: clock.now.advanced(by: .seconds(1)))
        }

        sleepTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await sleepTask.value
        }
        #expect(clock.pendingSleepCount == 0)
    }
}
