import AgentStudioTestHarness
import Testing

@testable import AgentStudioBridge

@Suite("Bridge Git read scheduler admission")
struct BridgeGitReadSchedulerAdmissionTests {
    @Test("queue and same-operation waiter admission stay within topology")
    func admissionBoundsQueueAndLogicalWaiters() async throws {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(
                maximumQueuedOperationCountPerClass: 2,
                maximumLogicalWaiterCountPerOperation: 2
            ),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let runningGate = HeldStep<Void>("runningGate", cancellation: .holdThroughCancellation)
        let firstQueuedGate = HeldStep<Void>("firstQueuedGate", cancellation: .holdThroughCancellation)
        let secondQueuedGate = HeldStep<Void>("secondQueuedGate", cancellation: .holdThroughCancellation)
        let rejectedGate = HeldStep<Void>("rejectedGate", cancellation: .holdThroughCancellation)
        let runningRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-running", key: "running")
            ) {
                try? await runningGate.arrive(())
                return "running"
            }
        }
        try await runningGate.firstArrival()
        let coalescedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-running", key: "running")
            ) {
                try? await runningGate.arrive(())
                return "running"
            }
        }
        _ = await eventProbe.waitFor(.coalesced)

        // Act
        let excessWaiterResult = await Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-running", key: "running")
            ) {
                try? await rejectedGate.arrive(())
                return "must-not-start"
            }
        }.result
        let firstQueuedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-queued-1", key: "queued-1")
            ) {
                try? await firstQueuedGate.arrive(())
                return "queued-1"
            }
        }
        let secondQueuedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-queued-2", key: "queued-2")
            ) {
                try? await secondQueuedGate.arrive(())
                return "queued-2"
            }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 3)
        let excessOperationResult = await Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-rejected", key: "rejected")
            ) {
                try? await rejectedGate.arrive(())
                return "must-not-start"
            }
        }.result
        let boundedSnapshot = await scheduler.snapshot()

        // Assert
        assertBridgeGitReadCapacityReached(excessWaiterResult)
        assertBridgeGitReadCapacityReached(excessOperationResult)
        #expect(boundedSnapshot.queuedCountByOperationClass[.reviewMetadata] == 2)
        #expect(boundedSnapshot.runningCountByOperationClass[.reviewMetadata] == 1)
        #expect(boundedSnapshot.logicalWaiterCount == 4)
        #expect(boundedSnapshot.scheduledDeadlineCount == 4)
        #expect(boundedSnapshot.activeOperationIds.count == 3)
        #expect(boundedSnapshot.occupiedSlotIds.count == 1)
        #expect(deadlineScheduler.activeDeadlineCount == 4)
        #expect(runningGate.recordedArrivals.count == 1)
        #expect(firstQueuedGate.recordedArrivals.isEmpty)
        #expect(secondQueuedGate.recordedArrivals.isEmpty)
        #expect(rejectedGate.recordedArrivals.isEmpty)

        firstQueuedRead.cancel()
        secondQueuedRead.cancel()
        _ = await eventProbe.waitFor(.logicalCancellation, occurrence: 2)
        assertBridgeGitReadCancelled(await firstQueuedRead.result)
        assertBridgeGitReadCancelled(await secondQueuedRead.result)
        let afterQueuedCancellationSnapshot = await scheduler.snapshot()
        #expect(afterQueuedCancellationSnapshot.queuedCountByOperationClass[.reviewMetadata] == nil)
        #expect(afterQueuedCancellationSnapshot.scheduledDeadlineCount == 2)
        #expect(deadlineScheduler.activeDeadlineCount == 2)

        runningGate.release()
        #expect(try await runningRead.value == "running")
        #expect(try await coalescedRead.value == "running")
        _ = await eventProbe.waitFor(.slotReleased)
        #expect(deadlineScheduler.activeDeadlineCount == 0)
        await assertBridgeGitReadAdmissionDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 1
        )
        await scheduler.shutdown()
    }

    @Test("Review A11 G7 never joins a draining A10 G7 physical read")
    func newerReviewAttemptStartsDistinctPhysicalReadWithinStableGeneration() async throws {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let firstGate = HeldStep<Void>("firstGate", cancellation: .holdThroughCancellation)
        let secondGate = HeldStep<Void>("secondGate", cancellation: .holdThroughCancellation)
        let firstRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(
                    worktree: "worktree-a",
                    key: "same-request",
                    freshnessKey: BridgeGitReadFreshnessKey(
                        token: "review-generation-7-attempt-10"
                    )
                )
            ) {
                try? await firstGate.arrive(())
                return "freshness-a"
            }
        }
        try await firstGate.firstArrival()
        let firstStart = await eventProbe.waitFor(.started)
        #expect(deadlineScheduler.fireNextActiveDeadline())
        _ = await eventProbe.waitFor(.draining)
        assertBridgeGitReadTimedOut(await firstRead.result)

        // Act
        let secondRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(
                    worktree: "worktree-a",
                    key: "same-request",
                    freshnessKey: BridgeGitReadFreshnessKey(
                        token: "review-generation-7-attempt-11"
                    )
                )
            ) {
                try? await secondGate.arrive(())
                return "freshness-b"
            }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 2)
        let whileFirstDrainsSnapshot = await scheduler.snapshot()
        firstGate.release()
        try await secondGate.firstArrival()
        let secondStart = await eventProbe.waitFor(.started, occurrence: 2)
        secondGate.release()
        let secondResult = try await secondRead.value
        _ = await eventProbe.waitFor(.slotReleased, occurrence: 2)

        // Assert
        #expect(secondResult == "freshness-b")
        #expect(firstStart.operationId != secondStart.operationId)
        #expect(whileFirstDrainsSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(whileFirstDrainsSnapshot.queuedCountByOperationClass[.reviewMetadata] == 1)
        #expect(firstGate.recordedArrivals.count == 1)
        #expect(secondGate.recordedArrivals.count == 1)
        #expect(eventProbe.events.count { $0.kind == .coalesced } == 0)
        await assertBridgeGitReadAdmissionDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 2
        )
        await scheduler.shutdown()
    }

    @Test("pre-cancelled caller leaves no scheduler residue")
    func preCancelledCallerIsRejectedBeforeAdmission() async {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let operationGate = HeldStep<Void>("operationGate", cancellation: .holdThroughCancellation)

        // Act
        let cancelledResult = await Task { () throws -> String in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "pre-cancelled")
            ) {
                try? await operationGate.arrive(())
                return "must-not-start"
            }
        }.result
        let snapshot = await scheduler.snapshot()

        // Assert
        assertBridgeGitReadCancelled(cancelledResult)
        #expect(eventProbe.events.isEmpty)
        #expect(operationGate.recordedArrivals.isEmpty)
        #expect(snapshot.activeOperationIds.isEmpty)
        #expect(snapshot.occupiedSlotIds.isEmpty)
        #expect(snapshot.logicalWaiterCount == 0)
        #expect(snapshot.scheduledDeadlineCount == 0)
        #expect(deadlineScheduler.activeDeadlineCount == 0)
        await assertBridgeGitReadAdmissionDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 0
        )
        await scheduler.shutdown()
    }
}

private func assertBridgeGitReadCapacityReached<ReturnValue>(
    _ result: Result<ReturnValue, Error>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .failure(let error) = result else {
        Issue.record("Expected capacity rejection", sourceLocation: sourceLocation)
        return
    }
    #expect(
        error as? BridgeGitReadSchedulerError == .capacityReached,
        sourceLocation: sourceLocation
    )
}

private func assertBridgeGitReadCancelled<ReturnValue>(
    _ result: Result<ReturnValue, Error>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .failure(let error) = result else {
        Issue.record("Expected cancellation", sourceLocation: sourceLocation)
        return
    }
    #expect(error is CancellationError, sourceLocation: sourceLocation)
}

private func assertBridgeGitReadTimedOut<ReturnValue>(
    _ result: Result<ReturnValue, Error>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .failure(let error) = result else {
        Issue.record("Expected a timeout", sourceLocation: sourceLocation)
        return
    }
    #expect(
        error as? BridgeGitReadSchedulerError == .timedOut,
        sourceLocation: sourceLocation
    )
}

private func assertBridgeGitReadAdmissionDrained(
    _ scheduler: BridgeGitReadScheduler,
    eventProbe: BridgeGitReadSchedulerEventProbe,
    expectedSlotReleaseCount: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let snapshot = await scheduler.snapshot()
    let releasedOperationIds = eventProbe.events
        .filter { $0.kind == .slotReleased }
        .map(\.operationId)
    #expect(releasedOperationIds.count == expectedSlotReleaseCount, sourceLocation: sourceLocation)
    #expect(Set(releasedOperationIds).count == expectedSlotReleaseCount, sourceLocation: sourceLocation)
    #expect(snapshot.activeOperationIds.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.occupiedSlotIds.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.logicalWaiterCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.scheduledDeadlineCount == 0, sourceLocation: sourceLocation)
}
