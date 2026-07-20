import Foundation
import _Concurrency

struct TestPushClock: Clock {
    typealias Duration = Swift.Duration

    private final class StateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var state = State()

        func withCriticalRegion<R>(_ body: (inout State) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }
    }

    struct Instant: Sendable, Comparable, Hashable, InstantProtocol {
        typealias Duration = TestPushClock.Duration

        fileprivate let nanoseconds: Int64

        func advanced(by duration: Self.Duration) -> Self {
            Self(nanoseconds: Self.toNanoseconds(from: duration) + nanoseconds)
        }

        func duration(to other: Self) -> Self.Duration {
            Self.Duration.nanoseconds(other.nanoseconds - nanoseconds)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.nanoseconds < rhs.nanoseconds
        }

        private static func toNanoseconds(from duration: Duration) -> Int64 {
            let components = duration.components
            let fromSeconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
            guard fromSeconds.overflow == false else { return fromSeconds.partialValue }
            return fromSeconds.partialValue + components.attoseconds / 1_000_000_000
        }
    }

    struct ScheduledSleep: Sendable {
        let generation: Int
        let deadline: Int64
        let continuation: UnsafeContinuation<Void, Error>
    }

    enum PendingSleepWaiterCondition {
        case atLeast(Int)
        case exactly(Int)
        case generation(Int)
        case atLeastFromGeneration(count: Int, generation: Int)

        func isSatisfied(by state: State) -> Bool {
            switch self {
            case .atLeast(let minimumCount):
                state.pending.count >= minimumCount
            case .exactly(let expectedCount):
                state.pending.count == expectedCount
            case .generation(let expectedGeneration):
                state.pending.contains { $0.generation == expectedGeneration }
            case .atLeastFromGeneration(let count, let generation):
                state.pending.filter { $0.generation >= generation }.count >= count
            }
        }
    }

    struct PendingSleepWaiter {
        let condition: PendingSleepWaiterCondition
        let continuation: UnsafeContinuation<Void, Never>
    }

    struct State {
        var generation: Int = 0
        var now: Int64 = 0
        var pending: [ScheduledSleep] = []
        var pendingSleepWaiters: [PendingSleepWaiter] = []
    }

    private let state = StateBox()

    var now: Instant {
        Instant(nanoseconds: state.withCriticalRegion { $0.now })
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let generation = state.withCriticalRegion { st in
            defer { st.generation += 1 }
            return st.generation
        }

        let _: Void = try await withTaskCancellationHandler(
            operation: {
                try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
                    var resumedWaiters: [UnsafeContinuation<Void, Never>] = []
                    var shouldThrowCancellation = false
                    let shouldResume = state.withCriticalRegion { st in
                        if Task.isCancelled {
                            shouldThrowCancellation = true
                            return true
                        }
                        if deadline.nanoseconds <= st.now {
                            return true
                        }

                        st.pending.append(
                            .init(
                                generation: generation,
                                deadline: deadline.nanoseconds,
                                continuation: continuation
                            ))
                        resumedWaiters = Self.dequeueSatisfiedPendingSleepWaiters(state: &st)
                        return false
                    }
                    for waiter in resumedWaiters {
                        waiter.resume()
                    }
                    if shouldResume {
                        if shouldThrowCancellation {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume()
                        }
                    }
                }
            },
            onCancel: {
                cancel(generation)
            }
        )
    }

    func advance(by duration: Duration) {
        let future = now.advanced(by: duration)
        advance(to: future)
    }

    func advance(to instant: Instant) {
        var ready: [UnsafeContinuation<Void, Error>] = []
        var resumedWaiters: [UnsafeContinuation<Void, Never>] = []
        state.withCriticalRegion { st in
            let nextNow = max(st.now, instant.nanoseconds)
            st.now = nextNow
            let remaining = st.pending.filter { $0.deadline > nextNow }
            let resumed = st.pending.filter { $0.deadline <= nextNow }
            st.pending = remaining
            ready = resumed.map { $0.continuation }
            resumedWaiters = Self.dequeueSatisfiedPendingSleepWaiters(state: &st)
        }

        for continuation in ready {
            continuation.resume()
        }
        for waiter in resumedWaiters {
            waiter.resume()
        }
    }

    var pendingSleepCount: Int {
        state.withCriticalRegion { $0.pending.count }
    }

    var scheduledSleepGeneration: Int {
        state.withCriticalRegion { $0.generation }
    }

    var pendingSleepGenerations: Set<Int> {
        state.withCriticalRegion { Set($0.pending.map(\.generation)) }
    }

    func waitForPendingSleepCount(atLeast count: Int = 1) async {
        await waitForPendingSleepCount(matching: .atLeast(count))
    }

    func waitForPendingSleepCount(exactly count: Int) async {
        await waitForPendingSleepCount(matching: .exactly(count))
    }

    func waitForPendingSleepGeneration(_ generation: Int) async {
        await waitForPendingSleepCount(matching: .generation(generation))
    }

    func waitForPendingSleepCount(atLeast count: Int, fromGeneration generation: Int) async {
        await waitForPendingSleepCount(matching: .atLeastFromGeneration(count: count, generation: generation))
    }

    private func waitForPendingSleepCount(matching condition: PendingSleepWaiterCondition) async {
        let shouldResumeImmediately = state.withCriticalRegion { st in
            condition.isSatisfied(by: st)
        }
        if shouldResumeImmediately {
            return
        }

        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            let shouldResume = state.withCriticalRegion { st in
                if condition.isSatisfied(by: st) {
                    return true
                }

                st.pendingSleepWaiters.append(
                    PendingSleepWaiter(condition: condition, continuation: continuation)
                )
                return false
            }

            if shouldResume {
                continuation.resume()
            }
        }
    }

    private func cancel(_ generation: Int) {
        var resumedWaiters: [UnsafeContinuation<Void, Never>] = []
        let continuation = state.withCriticalRegion { st -> UnsafeContinuation<Void, Error>? in
            guard let index = st.pending.firstIndex(where: { $0.generation == generation }) else {
                return nil
            }
            let continuation = st.pending.remove(at: index).continuation
            resumedWaiters = Self.dequeueSatisfiedPendingSleepWaiters(state: &st)
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
        for waiter in resumedWaiters {
            waiter.resume()
        }
    }

    private static func dequeueSatisfiedPendingSleepWaiters(
        state: inout State
    ) -> [UnsafeContinuation<Void, Never>] {
        guard !state.pendingSleepWaiters.isEmpty else { return [] }

        var remainingWaiters: [PendingSleepWaiter] = []
        var resumedWaiters: [UnsafeContinuation<Void, Never>] = []

        for waiter in state.pendingSleepWaiters {
            if waiter.condition.isSatisfied(by: state) {
                resumedWaiters.append(waiter.continuation)
            } else {
                remainingWaiters.append(waiter)
            }
        }

        state.pendingSleepWaiters = remainingWaiters
        return resumedWaiters
    }

    private static func nanoseconds(for duration: Duration) -> Int64 {
        let components = duration.components
        let fromSeconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard fromSeconds.overflow == false else { return fromSeconds.partialValue }
        return fromSeconds.partialValue + components.attoseconds / 1_000_000_000
    }
}
