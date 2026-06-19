import Foundation

enum GoodAsyncSleep {
    static func taskSleepNanoseconds(duration: Duration) async throws {
        try await Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)
    }
}

extension Duration {
    fileprivate var nanosecondsForTaskSleep: UInt64 {
        1
    }
}
