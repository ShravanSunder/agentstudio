import Foundation

/// Type-erased monotonic clock used by the Git refresh deadline owner.
/// Deadlines are durations from the captured origin, so production and injected
/// test clocks share the same ordering and cancellation semantics.
struct GitRefreshDeadlineClock: Sendable {
    private let nowValue: @Sendable () -> Duration
    private let sleepUntilValue: @Sendable (Duration) async throws -> Void

    init<SourceClock: Clock & Sendable>(_ sourceClock: SourceClock)
    where SourceClock.Duration == Duration {
        let origin = sourceClock.now
        nowValue = {
            origin.duration(to: sourceClock.now)
        }
        sleepUntilValue = { deadline in
            try await sourceClock.sleep(until: origin.advanced(by: deadline), tolerance: nil)
        }
    }

    var now: Duration {
        nowValue()
    }

    func sleep(until deadline: Duration) async throws {
        try await sleepUntilValue(deadline)
    }
}

enum GitRefreshDeadlineKind: Int, Sendable {
    case automatic
    case failure
    case capacityFallback
}

struct GitRefreshDeadlineEntry: Sendable {
    let deadline: Duration
    let kind: GitRefreshDeadlineKind
    let worktreeId: UUID
}

struct GitRefreshDeadlineQueue: Sendable {
    private var entries: [GitRefreshDeadlineEntry] = []

    var first: GitRefreshDeadlineEntry? {
        entries.first
    }

    mutating func insert(_ entry: GitRefreshDeadlineEntry) {
        entries.append(entry)
        var index = entries.count - 1
        while index > 0 {
            let parentIndex = (index - 1) / 2
            guard Self.isOrderedBefore(entries[index], entries[parentIndex]) else { break }
            entries.swapAt(index, parentIndex)
            index = parentIndex
        }
    }

    @discardableResult
    mutating func removeFirst() -> GitRefreshDeadlineEntry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 {
            return entries.removeLast()
        }
        let first = entries[0]
        entries[0] = entries.removeLast()
        var index = 0
        while true {
            let leftIndex = (index * 2) + 1
            guard leftIndex < entries.count else { break }
            let rightIndex = leftIndex + 1
            let nextIndex =
                rightIndex < entries.count && Self.isOrderedBefore(entries[rightIndex], entries[leftIndex])
                ? rightIndex : leftIndex
            guard Self.isOrderedBefore(entries[nextIndex], entries[index]) else { break }
            entries.swapAt(index, nextIndex)
            index = nextIndex
        }
        return first
    }

    private static func isOrderedBefore(
        _ lhs: GitRefreshDeadlineEntry,
        _ rhs: GitRefreshDeadlineEntry
    ) -> Bool {
        if lhs.deadline != rhs.deadline {
            return lhs.deadline < rhs.deadline
        }
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.worktreeId.uuidString < rhs.worktreeId.uuidString
    }
}
