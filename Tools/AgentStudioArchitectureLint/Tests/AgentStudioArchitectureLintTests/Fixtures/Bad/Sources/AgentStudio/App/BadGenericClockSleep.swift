import Foundation

enum BadGenericClockSleep {
    static func taskSleepForDuration() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    static func multilineTaskSleepForDuration() async throws {
        try await Task.sleep(
            for: .milliseconds(50)
        )
    }

    static func injectedClockSleep<C: Clock<Duration>>(_ clock: C) async throws {
        try await clock.sleep(for: .milliseconds(50))
    }
}
