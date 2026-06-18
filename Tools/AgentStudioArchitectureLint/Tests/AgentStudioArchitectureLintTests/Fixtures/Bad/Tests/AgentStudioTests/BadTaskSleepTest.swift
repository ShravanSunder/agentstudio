import Foundation

struct BadTaskSleepTest {
    func waitsWithOptionalTaskSleep() async {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }

    func waitsWithThrowingTaskSleep() async throws {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

    func waitsWithGenericClockTaskSleep() async throws {
        try await Task.sleep(for: .milliseconds(1))
    }

    func waitsWithMultilineTaskSleep() async throws {
        try await Task.sleep(
            nanoseconds: 1_000_000
        )
    }

    func waitsWithSpecializedTaskSleep() async throws {
        try await Task<Never, Never>.sleep(nanoseconds: 1_000_000)
    }

    func waitsWithQualifiedTaskSleep() async throws {
        try await Swift.Task.sleep(nanoseconds: 1_000_000)
    }
}
