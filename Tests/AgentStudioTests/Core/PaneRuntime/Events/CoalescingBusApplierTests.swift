import Foundation
import Testing

@testable import AgentStudio

@Suite("CoalescingBusApplier")
struct CoalescingBusApplierTests {
    @Test("coalesces many bus facts into one newest-wins MainActor batch")
    func coalescesManyBusFactsIntoOneNewestWinsMainActorBatch() async throws {
        let clock = TestPushClock()
        let recorder = ApplierBatchRecorder()
        let (stream, continuation) = AsyncStream.makeStream(
            of: ApplierFact.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        let applier = CoalescingBusApplier<UUID, ApplierPending, ApplierFact>(
            flushInterval: .milliseconds(25),
            delay: .clock(clock),
            accumulate: { pendingByWorktreeId, fact in
                pendingByWorktreeId[fact.worktreeId] = ApplierPending(
                    value: fact.value,
                    order: fact.order
                )
            },
            apply: { batch in
                recorder.record(batch)
            }
        )
        // Detached by design: this verifies accumulation is not MainActor-inherited.
        // swiftlint:disable:next no_task_detached
        let runTask = Task.detached {
            await applier.run(stream)
        }

        let firstWorktreeId = UUID()
        let secondWorktreeId = UUID()
        continuation.yield(ApplierFact(worktreeId: firstWorktreeId, value: "old", order: 1))
        continuation.yield(ApplierFact(worktreeId: secondWorktreeId, value: "only", order: 2))
        continuation.yield(ApplierFact(worktreeId: firstWorktreeId, value: "new", order: 3))

        let didScheduleFlush = await waitUntilYielding {
            clock.pendingSleepCount == 1
        }
        #expect(didScheduleFlush)
        clock.advance(by: .milliseconds(25))

        let didApplyOneBatch = await waitUntil {
            await recorder.batchCount == 1
        }
        #expect(didApplyOneBatch)

        continuation.finish()
        await runTask.value

        let batches = await recorder.batches
        #expect(batches.count == 1)
        #expect(batches[0][firstWorktreeId] == ApplierPending(value: "new", order: 3))
        #expect(batches[0][secondWorktreeId] == ApplierPending(value: "only", order: 2))
    }

    @Test("cancellation drains the pending batch before returning")
    func cancellationDrainsPendingBatchBeforeReturning() async throws {
        let clock = TestPushClock()
        let recorder = ApplierBatchRecorder()
        let (stream, continuation) = AsyncStream.makeStream(
            of: ApplierFact.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        let applier = CoalescingBusApplier<UUID, ApplierPending, ApplierFact>(
            flushInterval: .milliseconds(25),
            delay: .clock(clock),
            accumulate: { pendingByWorktreeId, fact in
                pendingByWorktreeId[fact.worktreeId] = ApplierPending(
                    value: fact.value,
                    order: fact.order
                )
            },
            apply: { batch in
                recorder.record(batch)
            }
        )
        // Detached by design: this verifies cancellation drains from an off-main consumer.
        // swiftlint:disable:next no_task_detached
        let runTask = Task.detached {
            await applier.run(stream)
        }

        let worktreeId = UUID()
        continuation.yield(ApplierFact(worktreeId: worktreeId, value: "pending", order: 1))

        let didScheduleFlush = await waitUntilYielding {
            clock.pendingSleepCount == 1
        }
        #expect(didScheduleFlush)

        runTask.cancel()
        continuation.finish()
        await runTask.value

        let batches = await recorder.batches
        #expect(batches.count == 1)
        #expect(batches[0][worktreeId] == ApplierPending(value: "pending", order: 1))
    }
}

private struct ApplierFact: Sendable {
    let worktreeId: UUID
    let value: String
    let order: Int
}

private struct ApplierPending: Equatable, Sendable {
    let value: String
    let order: Int
}

@MainActor
private final class ApplierBatchRecorder {
    private(set) var batches: [[UUID: ApplierPending]] = []

    var batchCount: Int {
        batches.count
    }

    func record(_ batch: [UUID: ApplierPending]) {
        batches.append(batch)
    }
}

private func waitUntil(
    maxTurns: Int = 10_000,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<maxTurns {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

private func waitUntilYielding(
    maxTurns: Int = 10_000,
    condition: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<maxTurns {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}
