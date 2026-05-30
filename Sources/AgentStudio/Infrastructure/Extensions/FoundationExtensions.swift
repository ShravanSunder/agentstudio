import Foundation

/// Small delay seam for production code that needs cancellation-aware sleeps.
///
/// Production code should default to `taskSleep`, which avoids the generic
/// clock sleep path that reproduced `swift_task_dealloc` crashes on macOS 26.4.
/// Tests can still inject `clock(_:)` for deterministic debounce/timer control.
struct AsyncDelay: Sendable {
    private let operation: @Sendable (Duration) async throws -> Void

    static let taskSleep = Self { duration in
        try await Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)
    }

    static func clock(_ clock: any Clock<Duration> & Sendable) -> Self {
        Self { duration in
            try await clock.sleep(for: duration)
        }
    }

    init(_ operation: @escaping @Sendable (Duration) async throws -> Void) {
        self.operation = operation
    }

    func wait(_ duration: Duration) async throws {
        try await operation(duration)
    }
}

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
