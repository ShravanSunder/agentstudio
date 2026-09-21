import Foundation

struct BadPollingWaitTest {
    func waitsUntilDeadline(condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
        }
    }

    func waitsForIterationBudget(condition: () -> Bool) async {
        for _ in 0..<20_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
    }

    func waitsBySleepingOnAClock(clock: any Clock<Duration>, condition: () -> Bool) async throws {
        repeat {
            try await clock.sleep(for: .milliseconds(5))
        } while !condition()
    }
}
