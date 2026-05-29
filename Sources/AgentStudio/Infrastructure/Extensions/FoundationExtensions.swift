import Foundation

extension Duration {
    /// Prefer `Task.sleep(nanoseconds:)` in production async tasks.
    ///
    /// Release builds on macOS 26.4 have reproduced Swift runtime
    /// `swift_task_dealloc` LIFO crashes in the generic
    /// clock-based sleep overload. Keeping sleep duration
    /// conversion explicit avoids that compiler/runtime path while preserving
    /// cancellation behavior for delayed async work.
    var nanosecondsForTaskSleep: UInt64 {
        let components = self.components
        guard components.seconds > 0 || components.attoseconds > 0 else {
            return 0
        }

        let secondsNanoseconds: UInt64
        if components.seconds > 0 {
            let seconds = UInt64(components.seconds)
            secondsNanoseconds =
                seconds > UInt64.max / 1_000_000_000
                ? UInt64.max
                : seconds * 1_000_000_000
        } else {
            secondsNanoseconds = 0
        }

        let attosecondNanoseconds =
            components.attoseconds > 0
            ? UInt64(components.attoseconds / 1_000_000_000)
            : 0
        let (nanoseconds, overflow) = secondsNanoseconds.addingReportingOverflow(attosecondNanoseconds)
        return overflow ? UInt64.max : nanoseconds
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        self?.trimmedNonEmpty
    }
}
