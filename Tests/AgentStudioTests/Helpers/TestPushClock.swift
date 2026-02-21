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
        fileprivate let nanoseconds: Int64

        func advanced(by duration: Duration) -> Instant {
            Instant(nanoseconds: TestPushClock.nanoseconds(for: duration) + nanoseconds)
        }

        func duration(to other: Instant) -> Duration {
            .nanoseconds(other.nanoseconds - nanoseconds)
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.nanoseconds < rhs.nanoseconds
        }
    }

    struct ScheduledSleep: Sendable {
        let generation: Int
        let deadline: Int64
        let continuation: UnsafeContinuation<Void, Error>
    }

    struct State {
        var generation: Int = 0
        var now: Int64 = 0
        var pending: [ScheduledSleep] = []
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
                    let shouldResume = state.withCriticalRegion { st in
                        if deadline.nanoseconds <= st.now {
                            return true
                        }

                        st.pending.append(
                            .init(
                                generation: generation,
                                deadline: deadline.nanoseconds,
                                continuation: continuation
                            ))
                        return false
                    }
                    if shouldResume {
                        continuation.resume()
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
        state.withCriticalRegion { st in
            let nextNow = max(st.now, instant.nanoseconds)
            st.now = nextNow
            let remaining = st.pending.filter { $0.deadline > nextNow }
            let resumed = st.pending.filter { $0.deadline <= nextNow }
            st.pending = remaining
            ready = resumed.map { $0.continuation }
        }

        for continuation in ready {
            continuation.resume()
        }
    }

    private func cancel(_ generation: Int) {
        let continuation = state.withCriticalRegion { st -> UnsafeContinuation<Void, Error>? in
            guard let index = st.pending.firstIndex(where: { $0.generation == generation }) else {
                return nil
            }
            return st.pending.remove(at: index).continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    private static func nanoseconds(for duration: Duration) -> Int64 {
        let components = duration.components
        let fromSeconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard fromSeconds.overflow == false else { return fromSeconds.partialValue }
        return fromSeconds.partialValue + components.attoseconds / 1_000_000_000
    }
}
