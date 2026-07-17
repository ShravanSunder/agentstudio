import Testing

@testable import AgentStudio

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
        let runningGate = BridgeGitReadOperationGate(returnValue: "running")
        let firstQueuedGate = BridgeGitReadOperationGate(returnValue: "queued-1")
        let secondQueuedGate = BridgeGitReadOperationGate(returnValue: "queued-2")
        let rejectedGate = BridgeGitReadOperationGate(returnValue: "must-not-start")
        let runningRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-running", key: "running")
            ) { await runningGate.run() }
        }
        await runningGate.waitUntilStarted()
        let coalescedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-running", key: "running")
            ) { await runningGate.run() }
        }
        _ = await eventProbe.waitFor(.coalesced)

        // Act
        let excessWaiterResult = await Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-running", key: "running")
            ) { await rejectedGate.run() }
        }.result
        let firstQueuedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-queued-1", key: "queued-1")
            ) { await firstQueuedGate.run() }
        }
        let secondQueuedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-queued-2", key: "queued-2")
            ) { await secondQueuedGate.run() }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 3)
        let excessOperationResult = await Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-rejected", key: "rejected")
            ) { await rejectedGate.run() }
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
        #expect(await runningGate.recordedInvocationCount() == 1)
        #expect(await firstQueuedGate.recordedInvocationCount() == 0)
        #expect(await secondQueuedGate.recordedInvocationCount() == 0)
        #expect(await rejectedGate.recordedInvocationCount() == 0)

        firstQueuedRead.cancel()
        secondQueuedRead.cancel()
        _ = await eventProbe.waitFor(.logicalCancellation, occurrence: 2)
        assertBridgeGitReadCancelled(await firstQueuedRead.result)
        assertBridgeGitReadCancelled(await secondQueuedRead.result)
        let afterQueuedCancellationSnapshot = await scheduler.snapshot()
        #expect(afterQueuedCancellationSnapshot.queuedCountByOperationClass[.reviewMetadata] == nil)
        #expect(afterQueuedCancellationSnapshot.scheduledDeadlineCount == 2)
        #expect(deadlineScheduler.activeDeadlineCount == 2)

        await runningGate.release()
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

    @Test("freshness change never coalesces with a draining physical read")
    func freshnessChangeStartsDistinctPhysicalRead() async throws {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let firstGate = BridgeGitReadOperationGate(returnValue: "freshness-a")
        let secondGate = BridgeGitReadOperationGate(returnValue: "freshness-b")
        let firstRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(
                    worktree: "worktree-a",
                    key: "same-request",
                    freshnessKey: BridgeGitReadFreshnessKey(token: "freshness-a")
                )
            ) { await firstGate.run() }
        }
        await firstGate.waitUntilStarted()
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
                    freshnessKey: BridgeGitReadFreshnessKey(token: "freshness-b")
                )
            ) { await secondGate.run() }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 2)
        let whileFirstDrainsSnapshot = await scheduler.snapshot()
        await firstGate.release()
        await secondGate.waitUntilStarted()
        let secondStart = await eventProbe.waitFor(.started, occurrence: 2)
        await secondGate.release()
        let secondResult = try await secondRead.value
        _ = await eventProbe.waitFor(.slotReleased, occurrence: 2)

        // Assert
        #expect(secondResult == "freshness-b")
        #expect(firstStart.operationId != secondStart.operationId)
        #expect(whileFirstDrainsSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(whileFirstDrainsSnapshot.queuedCountByOperationClass[.reviewMetadata] == 1)
        #expect(await firstGate.recordedInvocationCount() == 1)
        #expect(await secondGate.recordedInvocationCount() == 1)
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
        let operationGate = BridgeGitReadOperationGate(returnValue: "must-not-start")

        // Act
        let cancelledResult = await Task { () throws -> String in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "pre-cancelled")
            ) { await operationGate.run() }
        }.result
        let snapshot = await scheduler.snapshot()

        // Assert
        assertBridgeGitReadCancelled(cancelledResult)
        #expect(eventProbe.events.isEmpty)
        #expect(await operationGate.recordedInvocationCount() == 0)
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
