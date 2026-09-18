import Dispatch
import Foundation

/// Runs blocking work on a libdispatch thread and suspends the caller until it
/// finishes.
///
/// Swift Testing runs each test body as a task on the cooperative executor,
/// whose width is the machine's core count. A synchronous socket read, a
/// semaphore wait or a subprocess wait on that thread removes it from the pool
/// for as long as it blocks. `AgentStudioAppIPCServer` answers every accepted
/// connection from a `Task` on that same pool, so a test blocking there is
/// starving the server it is waiting on. On a three-core CI runner three such
/// tests at once deadlocked the entire fast lane, and the sample showed all
/// three cooperative threads parked in `recv` and `semaphore_wait_trap`.
///
/// `DispatchQueue.global()` is a different pool from
/// `com.apple.root.default-qos.cooperative` and grows threads on demand, so the
/// block lands somewhere that can afford it. `@concurrent` is not a substitute:
/// it still draws from the cooperative pool.
///
/// Every synchronous `UnixSocketConnection.receive`, `DispatchSemaphore.wait`
/// and `Process` wait in a test body goes through here or through one of the
/// `WithoutBlockingMainActor` helpers built on the same hop. The
/// `agentstudio_test_blocking_wait_off_cooperative_pool` lint rule enforces it.
package func withoutBlockingCooperativePool<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(returning: try blockingWork())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// The non-throwing form, for a wait that reports through its own return value
/// rather than by throwing, such as `DispatchSemaphore.wait(timeout:)`.
package func withoutBlockingCooperativePool<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () -> Value
) async -> Value {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: blockingWork())
        }
    }
}
