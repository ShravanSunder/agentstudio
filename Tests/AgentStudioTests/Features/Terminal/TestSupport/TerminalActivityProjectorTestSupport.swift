import AgentStudioInfrastructure
import Foundation

@testable import AgentStudioTerminal

/// Thread-safe recorder for `TerminalActivityProjector` outcome batches, with
/// predicate-based async waiting. Shared across the projector test files that
/// split by responsibility (general aggregate/window behavior vs.
/// commandFinished settle behavior).
final class OutcomeRecorder: @unchecked Sendable {
    private enum OutcomeWaitError: Error {
        case timedOut
    }

    private struct OutcomeWaiter {
        let id: Int
        let predicate: @Sendable ([TerminalActivityProjectionOutcome]) -> Bool
        let continuation: CheckedContinuation<[TerminalActivityProjectionOutcome], any Error>
    }

    private let lock = NSLock()
    private var nextOutcomeWaiterID = 0
    private var recordedOutcomes: [TerminalActivityProjectionOutcome] = []
    private var recordedBatches: [[TerminalActivityProjectionOutcome]] = []
    private var outcomeWaiters: [OutcomeWaiter] = []

    var outcomes: [TerminalActivityProjectionOutcome] {
        lock.withLock { recordedOutcomes }
    }

    var batches: [[TerminalActivityProjectionOutcome]] {
        lock.withLock { recordedBatches }
    }

    func record(_ batch: [TerminalActivityProjectionOutcome]) {
        var completedWaiters: [OutcomeWaiter] = []
        var outcomeSnapshot: [TerminalActivityProjectionOutcome] = []
        lock.withLock {
            recordedBatches.append(batch)
            recordedOutcomes.append(contentsOf: batch)
            outcomeSnapshot = recordedOutcomes
            outcomeWaiters.removeAll { waiter in
                guard waiter.predicate(outcomeSnapshot) else { return false }
                completedWaiters.append(waiter)
                return true
            }
        }
        for waiter in completedWaiters {
            waiter.continuation.resume(returning: outcomeSnapshot)
        }
    }

    func firstSnapshot(
        timeout: Duration = .seconds(10),
        where predicate: @escaping @Sendable ([TerminalActivityProjectionOutcome]) -> Bool
    ) async throws -> [TerminalActivityProjectionOutcome] {
        try await withThrowingTaskGroup(of: [TerminalActivityProjectionOutcome].self) { group in
            group.addTask {
                try await self.waitForSnapshot(where: predicate)
            }
            group.addTask {
                try await AsyncDelay.taskSleep.wait(timeout)
                throw OutcomeWaitError.timedOut
            }
            defer { group.cancelAll() }
            guard let snapshot = try await group.next() else {
                throw CancellationError()
            }
            return snapshot
        }
    }

    private func waitForSnapshot(
        where predicate: @escaping @Sendable ([TerminalActivityProjectionOutcome]) -> Bool
    ) async throws -> [TerminalActivityProjectionOutcome] {
        let waiterID = lock.withLock {
            defer { nextOutcomeWaiterID += 1 }
            return nextOutcomeWaiterID
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var immediateResult: Result<[TerminalActivityProjectionOutcome], any Error>?
                lock.withLock {
                    if Task.isCancelled {
                        immediateResult = .failure(CancellationError())
                    } else if predicate(recordedOutcomes) {
                        immediateResult = .success(recordedOutcomes)
                    } else {
                        outcomeWaiters.append(
                            OutcomeWaiter(
                                id: waiterID,
                                predicate: predicate,
                                continuation: continuation
                            )
                        )
                    }
                }
                if let immediateResult {
                    continuation.resume(with: immediateResult)
                }
            }
        } onCancel: {
            self.cancelOutcomeWaiter(id: waiterID)
        }
    }

    private func cancelOutcomeWaiter(id: Int) {
        let continuation = lock.withLock {
            guard let index = outcomeWaiters.firstIndex(where: { $0.id == id }) else {
                return nil as CheckedContinuation<[TerminalActivityProjectionOutcome], any Error>?
            }
            return outcomeWaiters.remove(at: index).continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}

/// A settable raw-viewport-text source for tests that need the mocked
/// `lastOutputLineReader` to return different text across successive
/// settles (e.g. simulating the shell prompt changing between commands).
final class MutableRawViewportTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?

    init(_ text: String?) {
        self.text = text
    }

    func set(_ text: String?) {
        lock.withLock { self.text = text }
    }

    func read() -> String? {
        lock.withLock { text }
    }
}
