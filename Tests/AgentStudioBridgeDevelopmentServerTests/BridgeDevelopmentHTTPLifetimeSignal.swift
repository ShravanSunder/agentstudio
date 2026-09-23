import Synchronization

/// One-shot latch for an HTTP lifetime fact that the server already reports through a
/// callback: stream cancellation, the first response-body write, or the channel closing.
///
/// The owner's callback calls `signal()` and every waiter resumes. Nothing polls and there
/// is no deadline, because whether the socket layer delivers one of these facts is a
/// product fact rather than a machine-speed fact; the lane's inactivity watchdog is the
/// hang bound, and it names the test that was still waiting.
///
/// Shared by `BridgeDevelopmentHTTPStreamLifetimeTests` and
/// `BridgeDevelopmentHTTPResponseCancellationTests`, which previously carried two
/// byte-identical spin-over-`Mutex(Bool)` probes.
final class BridgeDevelopmentHTTPLifetimeSignal: Sendable {
    private struct SignalState {
        var isSignalled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(SignalState())

    /// Single unbarriered read, for negative claims that are already ordered behind a
    /// later published fact (see the completed request/response round trip in
    /// `BridgeDevelopmentHTTPResponseCancellationTests`). Never poll this.
    var isSignalled: Bool { state.withLock(\.isSignalled) }

    /// Marks the fact as delivered and releases everyone waiting on it. Idempotent: the
    /// owning callbacks can fire more than once per connection.
    func signal() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isSignalled = true
            let pending = state.waiters
            state.waiters.removeAll()
            return pending
        }
        // Resume outside the lock: a resumed waiter can re-enter the owning callback.
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Suspends until the fact has been delivered, returning at once if it already has, so
    /// there is no lost-wakeup window between the check and the suspension.
    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadySignalled = state.withLock { state -> Bool in
                if state.isSignalled {
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if alreadySignalled {
                continuation.resume()
            }
        }
    }
}
