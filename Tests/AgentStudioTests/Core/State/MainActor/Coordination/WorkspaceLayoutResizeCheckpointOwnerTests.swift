import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace layout resize checkpoint owner")
struct WorkspaceLayoutResizeCheckpointOwnerTests {
    @Test("128 offers retain one worker and commit only the latest checkpoint")
    func manyOffersCommitOnlyLatestCheckpoint() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = WorkspaceLayoutResizeCheckpointOwnerRecorder(
            result: .unchanged(revision: .zero)
        )
        let owner = WorkspaceLayoutResizeCheckpointOwner(
            target: checkpoint(sequence: 1).target,
            quietWindow: .milliseconds(50),
            clock: clock,
            committer: recorder.commit,
            observer: recorder.observe
        )

        // Act
        #expect(owner.offer(checkpoint(sequence: 1)) == .accepted(.scheduled))
        await clock.waitForPendingSleepCount(exactly: 1)
        for sequence in 2...128 {
            #expect(owner.offer(checkpoint(sequence: sequence)) == .accepted(.replacedPending))
        }
        clock.advance(by: .milliseconds(50))
        await recorder.waitForObservedCount(1)

        // Assert
        let latestCheckpoint = checkpoint(sequence: 128)
        #expect(recorder.committedCheckpoints == [latestCheckpoint])
        #expect(recorder.observedCheckpoints == [latestCheckpoint])
        #expect(recorder.observedResults == [.unchanged(revision: .zero)])
        #expect(clock.scheduledSleepGeneration == 1)
        #expect(owner.diagnostics.acceptedOfferCount == 128)
        #expect(owner.diagnostics.replacedOfferCount == 127)
        #expect(owner.diagnostics.unchangedOfferCount == 0)
        #expect(owner.diagnostics.workerTaskStartCount == 1)
        #expect(owner.diagnostics.settledValueCount == 1)
    }

    @Test("flush commits once and cancelled delayed settlement cannot repeat")
    func flushCommitsOnceWithoutDelayedRepeat() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = WorkspaceLayoutResizeCheckpointOwnerRecorder(
            result: .unchanged(revision: .zero)
        )
        let owner = WorkspaceLayoutResizeCheckpointOwner(
            target: checkpoint(sequence: 7).target,
            quietWindow: .seconds(1),
            clock: clock,
            committer: recorder.commit,
            observer: recorder.observe
        )
        let offeredCheckpoint = checkpoint(sequence: 7)
        #expect(owner.offer(offeredCheckpoint) == .accepted(.scheduled))
        await clock.waitForPendingSleepCount(exactly: 1)

        // Act
        let firstFlush = owner.flushNow()
        let secondFlush = owner.flushNow()
        await clock.waitForPendingSleepCount(exactly: 0)
        clock.advance(by: .seconds(2))

        // Assert
        #expect(firstFlush == .flushed)
        #expect(secondFlush == .noPendingValue)
        #expect(recorder.committedCheckpoints == [offeredCheckpoint])
        #expect(recorder.observedCheckpoints == [offeredCheckpoint])
        #expect(recorder.observedResults == [.unchanged(revision: .zero)])
        #expect(owner.diagnostics.workerTaskStartCount == 1)
        #expect(owner.diagnostics.settledValueCount == 1)
    }

    @Test("close discards pending checkpoint and rejects later work")
    func closeDiscardsPendingCheckpoint() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = WorkspaceLayoutResizeCheckpointOwnerRecorder(
            result: .unchanged(revision: .zero)
        )
        let owner = WorkspaceLayoutResizeCheckpointOwner(
            target: checkpoint(sequence: 3).target,
            quietWindow: .seconds(1),
            clock: clock,
            committer: recorder.commit,
            observer: recorder.observe
        )
        #expect(owner.offer(checkpoint(sequence: 3)) == .accepted(.scheduled))
        await clock.waitForPendingSleepCount(exactly: 1)

        // Act
        let firstClose = owner.close()
        let repeatedClose = owner.close()
        let closedOffer = owner.offer(checkpoint(sequence: 4))
        let closedFlush = owner.flushNow()
        await clock.waitForPendingSleepCount(exactly: 0)
        clock.advance(by: .seconds(2))

        // Assert
        #expect(firstClose == .closedDiscardingPendingValue)
        #expect(repeatedClose == .alreadyClosed)
        #expect(closedOffer == .accepted(.rejectedClosed))
        #expect(closedFlush == .rejectedClosed)
        #expect(recorder.committedCheckpoints.isEmpty)
        #expect(recorder.observedCheckpoints.isEmpty)
        #expect(recorder.observedResults.isEmpty)
        #expect(owner.diagnostics.settledValueCount == 0)
    }

    @Test("committer rejection is observed exactly once")
    func committerRejectionIsObservedExactlyOnce() async {
        // Arrange
        let clock = TestPushClock()
        let rejection = WorkspaceLayoutResizePersistenceResult.rejected(
            .compositionDomainNotInstalled(phase: .preinstall)
        )
        let recorder = WorkspaceLayoutResizeCheckpointOwnerRecorder(result: rejection)
        let offeredCheckpoint = checkpoint(sequence: 9)
        let owner = WorkspaceLayoutResizeCheckpointOwner(
            target: offeredCheckpoint.target,
            quietWindow: .milliseconds(25),
            clock: clock,
            committer: recorder.commit,
            observer: recorder.observe
        )
        // Act
        #expect(owner.offer(offeredCheckpoint) == .accepted(.scheduled))
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(25))
        await recorder.waitForObservedCount(1)
        clock.advance(by: .seconds(1))

        // Assert
        #expect(owner.flushNow() == .noPendingValue)
        #expect(recorder.committedCheckpoints == [offeredCheckpoint])
        #expect(recorder.observedCheckpoints == [offeredCheckpoint])
        #expect(recorder.observedResults == [rejection])
        #expect(owner.diagnostics.settledValueCount == 1)
    }

    @Test("a target-bound owner rejects a different target without replacing pending custody")
    func differentTargetIsRejectedWithoutReplacingPendingCustody() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = WorkspaceLayoutResizeCheckpointOwnerRecorder(
            result: .unchanged(revision: .zero)
        )
        let firstTargetCheckpoint = checkpoint(sequence: 1)
        let differentTargetCheckpoint = WorkspaceLayoutResizeCheckpoint.mainSplit(
            tabID: UUIDv7.generate(),
            arrangementID: UUIDv7.generate(),
            splitID: UUIDv7.generate(),
            ratio: 0.6
        )
        let owner = WorkspaceLayoutResizeCheckpointOwner(
            target: firstTargetCheckpoint.target,
            quietWindow: .milliseconds(25),
            clock: clock,
            committer: recorder.commit,
            observer: recorder.observe
        )

        // Act
        #expect(owner.offer(firstTargetCheckpoint) == .accepted(.scheduled))
        await clock.waitForPendingSleepCount(exactly: 1)
        let mismatch = owner.offer(differentTargetCheckpoint)
        clock.advance(by: .milliseconds(25))
        await recorder.waitForObservedCount(1)

        // Assert
        #expect(
            mismatch
                == .rejectedTargetMismatch(
                    expected: firstTargetCheckpoint.target,
                    actual: differentTargetCheckpoint.target
                )
        )
        #expect(recorder.committedCheckpoints == [firstTargetCheckpoint])
        #expect(owner.diagnostics.replacedOfferCount == 0)
        #expect(owner.diagnostics.settledValueCount == 1)
    }

    private func checkpoint(sequence: Int) -> WorkspaceLayoutResizeCheckpoint {
        .mainSplit(
            tabID: UUID(uuidString: "00000000-0000-7000-8000-000000000001")!,
            arrangementID: UUID(uuidString: "00000000-0000-7000-8000-000000000002")!,
            splitID: UUID(uuidString: "00000000-0000-7000-8000-000000000003")!,
            ratio: 0.2 + (Double(sequence) / 1000)
        )
    }
}

@MainActor
private final class WorkspaceLayoutResizeCheckpointOwnerRecorder {
    private let result: WorkspaceLayoutResizePersistenceResult
    private var observedCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    private(set) var committedCheckpoints: [WorkspaceLayoutResizeCheckpoint] = []
    private(set) var observedCheckpoints: [WorkspaceLayoutResizeCheckpoint] = []
    private(set) var observedResults: [WorkspaceLayoutResizePersistenceResult] = []

    init(result: WorkspaceLayoutResizePersistenceResult) {
        self.result = result
    }

    func commit(_ checkpoint: WorkspaceLayoutResizeCheckpoint) -> WorkspaceLayoutResizePersistenceResult {
        committedCheckpoints.append(checkpoint)
        return result
    }

    func observe(
        _ checkpoint: WorkspaceLayoutResizeCheckpoint,
        _ result: WorkspaceLayoutResizePersistenceResult
    ) {
        observedCheckpoints.append(checkpoint)
        observedResults.append(result)
        let readyWaiters = observedCountWaiters.filter { observedCheckpoints.count >= $0.count }
        observedCountWaiters.removeAll { observedCheckpoints.count >= $0.count }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    func waitForObservedCount(_ count: Int) async {
        guard observedCheckpoints.count < count else { return }
        await withCheckedContinuation { continuation in
            observedCountWaiters.append((count: count, continuation: continuation))
        }
    }
}
