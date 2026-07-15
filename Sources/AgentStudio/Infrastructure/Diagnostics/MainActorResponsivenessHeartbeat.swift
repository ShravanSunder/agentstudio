import Foundation

enum MainActorHeartbeatObservation: Equatable, Sendable {
    case firstPulse
    case observed(MainActorHeartbeatRecord)
    case missingPulse
}

struct MainActorHeartbeatRecord: Equatable, Sendable {
    let gapNanoseconds: UInt64
    let overdue: MainActorHeartbeatOverdue
}

enum MainActorHeartbeatOverdue: Equatable, Sendable {
    case withinBudget
    case overdue(consecutiveCount: UInt64)
}

final class MainActorResponsivenessHeartbeat: @unchecked Sendable {
    private let clock: any PerformanceMonotonicClock
    private let expectedIntervalNanoseconds: UInt64
    private let lock = NSLock()
    private var lastPulse: PerformanceMonotonicInstant?
    private var consecutiveOverdueCount: UInt64 = 0

    init(
        expectedIntervalNanoseconds: UInt64,
        clock: any PerformanceMonotonicClock = SystemPerformanceMonotonicClock()
    ) {
        precondition(expectedIntervalNanoseconds > 0)
        self.expectedIntervalNanoseconds = expectedIntervalNanoseconds
        self.clock = clock
    }

    @MainActor
    func pulse() -> MainActorHeartbeatObservation {
        lock.withLock {
            let now = clock.now()
            guard let previous = lastPulse else {
                lastPulse = now
                consecutiveOverdueCount = 0
                return .firstPulse
            }
            guard now >= previous else {
                lastPulse = nil
                consecutiveOverdueCount = 0
                return .missingPulse
            }
            lastPulse = now
            let gap = now.uptimeNanoseconds - previous.uptimeNanoseconds
            if gap > expectedIntervalNanoseconds {
                consecutiveOverdueCount = min(consecutiveOverdueCount + 1, UInt64.max)
                return .observed(
                    MainActorHeartbeatRecord(
                        gapNanoseconds: gap,
                        overdue: .overdue(consecutiveCount: consecutiveOverdueCount)
                    ))
            }
            consecutiveOverdueCount = 0
            return .observed(MainActorHeartbeatRecord(gapNanoseconds: gap, overdue: .withinBudget))
        }
    }

    func reset() {
        lock.withLock {
            lastPulse = nil
            consecutiveOverdueCount = 0
        }
    }

    func observationWithoutPulse() -> MainActorHeartbeatObservation {
        lock.withLock {
            lastPulse == nil ? .missingPulse : .firstPulse
        }
    }
}
