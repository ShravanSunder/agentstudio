import Testing

@Suite("Test push clock")
struct TestPushClockTests {
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
