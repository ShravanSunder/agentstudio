import Foundation

/// One workspace's synchronous admission order for Bridge writes. The App
/// composition shares this instance between UI saves and membership commands.
package struct BridgeWriteGeneration: Comparable, Hashable, Sendable {
    package let value: Int

    package init(value: Int) {
        precondition(value >= 0)
        self.value = value
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

@MainActor
package final class BridgeNavigationWriteSequencer {
    private var latest = BridgeWriteGeneration(value: 0)

    package init() {}

    package func nextTicket() -> BridgeWriteGeneration {
        latest = BridgeWriteGeneration(value: latest.value + 1)
        return latest
    }

    /// Hydration raises the floor before a startup reconciliation can save.
    package func restoreFloor(_ floor: BridgeWriteGeneration) {
        if floor > latest { latest = floor }
    }
}
