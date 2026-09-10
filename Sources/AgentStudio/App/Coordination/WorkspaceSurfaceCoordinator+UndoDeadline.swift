import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

extension WorkspaceSurfaceCoordinator {
    func signalUndoDeadlineChange() {
        if undoDeadlineTask == nil {
            let wakeups = undoDeadlineWakeups
            let clock = undoClock
            let delay = undoDelay
            undoDeadlineTask = Task { [weak self] in
                await Self.runUndoDeadlineLoop(wakeups: wakeups, clock: clock, delay: delay) { [weak self] time in
                    try await self?.expireUndoAndReadNextDeadline(time: time)
                }
            }
        }
        undoDeadlineWakeups.continuation.yield(())
    }

    private func expireUndoAndReadNextDeadline(time: WorkspaceUndoJournalTime) async throws -> Int64? {
        let retired = try await store.expireUndoCloses(time: time)
        // A committed retirement is delivered even if cancellation arrived during SQLite I/O.
        consumeUndoRetirements(retired)
        guard !Task.isCancelled else { return nil }
        return try await store.nextUndoDeadline(bootID: time.bootID)
    }

    /// Wakeups request a fresh database decision; they do not carry ownership transitions.
    /// One loop owns and joins its single sleeper, including cancellation during a database check.
    @concurrent nonisolated private static func runUndoDeadlineLoop(
        wakeups: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation),
        clock: @escaping @Sendable () async throws -> WorkspaceUndoJournalTime,
        delay: AsyncDelay,
        check: @escaping @MainActor @Sendable (WorkspaceUndoJournalTime) async throws -> Int64?
    ) async {
        var sleeper: Task<Void, Never>?
        for await _ in wakeups.stream {
            sleeper?.cancel()
            await sleeper?.value
            sleeper = nil
            guard !Task.isCancelled else { break }

            let waitDuration: Duration
            do {
                let time = try await clock()
                guard let deadline = try await check(time) else { continue }
                guard !Task.isCancelled else { break }
                let current = try await clock()
                waitDuration =
                    current.bootID == time.bootID
                    ? .nanoseconds(max(0, deadline - current.uptimeNanoseconds))
                    : AppPolicies.WorkspacePersistence.undoDeadlineRetryDelay
            } catch {
                guard !Task.isCancelled else { break }
                waitDuration = AppPolicies.WorkspacePersistence.undoDeadlineRetryDelay
            }

            sleeper = Task {
                do {
                    try await delay.wait(waitDuration)
                    guard !Task.isCancelled else { return }
                    wakeups.continuation.yield(())
                } catch {
                    // Cancellation is the normal reschedule path for the injected clock.
                }
            }
        }
        sleeper?.cancel()
        await sleeper?.value
    }
}
