import Foundation

/// Monotonic revision counter per store. Shared across all push plans
/// for a pane to ensure revision ordering per section 5.7.
///
/// Each `BridgePaneController` owns one `RevisionClock` instance.
/// When a push plan fires, it calls `next(for:)` to stamp the payload
/// with a monotonically increasing revision number. The React-side
/// store uses this to detect and discard stale pushes.
@MainActor
final class RevisionClock {
    private var counters: [StoreKey: Int] = [:]

    /// Returns the next revision number for the given store.
    /// Starts at 1 and increments by 1 on each call, independently per store.
    func next(for store: StoreKey) -> Int {
        let value = (counters[store] ?? 0) + 1
        counters[store] = value
        return value
    }
}
