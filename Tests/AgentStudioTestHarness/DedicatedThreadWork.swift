import Foundation

/// Runs blocking work on a thread of its own and returns what it produced.
///
/// For the test side of a synchronous seam: a socket `stop()`, a blocking
/// receive, or a call that parks in ``HeldStep/arriveBlocking(_:)``. The block
/// lands on a new thread rather than a cooperative-pool thread, so the test
/// task stays free to await ``HeldStep/firstArrival()`` and end the step while
/// the work is parked. The work itself cannot be cancelled; the runner's hang
/// bound is what ends a call that never returns.
package func valueFromDedicatedThread<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(with: Result { try blockingWork() })
        }
    }
}
