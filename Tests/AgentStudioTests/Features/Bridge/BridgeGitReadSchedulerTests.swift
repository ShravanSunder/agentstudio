import AgentStudioTestHarness
import Testing

@testable import AgentStudioBridge

@Suite("Bridge Git read scheduler")
struct BridgeGitReadSchedulerTests {
    @Test("same typed worktree operation coalesces one physical read")
    func coalescesMatchingLogicalWaiters() async throws {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let operationGate = HeldStep<Void>("operationGate", cancellation: .holdThroughCancellation)
        let request = makeBridgeGitReadRequest(worktree: "worktree-a", key: "metadata-head")
        let firstRead = Task {
            try await scheduler.read(request: request) {
                try? await operationGate.arrive(())
                return "shared-result"
            }
        }
        try await operationGate.firstArrival()

        // Act
        let secondRead = Task {
            try await scheduler.read(request: request) {
                try? await operationGate.arrive(())
                return "shared-result"
            }
        }
        _ = await eventProbe.waitFor(.coalesced)
        let coalescedSnapshot = await scheduler.snapshot()
        operationGate.release()
        let firstResult = try await firstRead.value
        let secondResult = try await secondRead.value

        // Assert
        #expect(firstResult == "shared-result")
        #expect(secondResult == "shared-result")
        #expect(operationGate.recordedArrivals.count == 1)
        #expect(coalescedSnapshot.logicalWaiterCount == 2)
        #expect(coalescedSnapshot.coalescedLogicalWaiterCount == 1)
        #expect(coalescedSnapshot.scheduledDeadlineCount == 2)
        _ = await eventProbe.waitFor(.slotReleased)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 1
        )
        await scheduler.shutdown()
    }

    @Test("logical timeout keeps its physical slot draining until true return")
    func timeoutRetainsPhysicalCustodyAndPreventsBackfill() async throws {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let blockedGate = HeldStep<Void>("blockedGate", cancellation: .holdThroughCancellation)
        let backfillGate = HeldStep<Void>("backfillGate", cancellation: .holdThroughCancellation)
        let blockedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "blocked")
            ) {
                try? await blockedGate.arrive(())
                return "late"
            }
        }
        try await blockedGate.firstArrival()
        let blockedStart = await eventProbe.waitFor(.started)

        // Act
        #expect(deadlineScheduler.fireNextActiveDeadline())
        _ = await eventProbe.waitFor(.draining)
        let timedOutResult = await blockedRead.result
        let backfillRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-b", key: "backfill")
            ) {
                try? await backfillGate.arrive(())
                return "backfill"
            }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 2)
        let drainingSnapshot = await scheduler.snapshot()

        // Assert
        assertBridgeGitReadTimedOut(timedOutResult)
        #expect(drainingSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(drainingSnapshot.queuedCountByOperationClass[.reviewMetadata] == 1)
        #expect(drainingSnapshot.occupiedSlotIds == [BridgeGitReadSlotID(token: "metadata-slot-1")])
        #expect(backfillGate.recordedArrivals.isEmpty)

        blockedGate.release()
        try await backfillGate.firstArrival()
        let backfillStart = await eventProbe.waitFor(.started, occurrence: 2)
        #expect(blockedStart.operationId != backfillStart.operationId)
        let firstReleaseEvents = eventProbe.events.filter {
            $0.kind == .slotReleased && $0.operationId == blockedStart.operationId
        }
        #expect(firstReleaseEvents.count == 1)
        backfillGate.release()
        #expect(try await backfillRead.value == "backfill")
        _ = await eventProbe.waitFor(.slotReleased, occurrence: 2)
        let finalSnapshot = await scheduler.snapshot()
        #expect(finalSnapshot.activeOperationIds.isEmpty)
        #expect(finalSnapshot.occupiedSlotIds.isEmpty)
        #expect(finalSnapshot.logicalWaiterCount == 0)
        let releasedOperationIds = eventProbe.events
            .filter { $0.kind == .slotReleased }
            .map(\.operationId)
        #expect(releasedOperationIds.count == 2)
        #expect(Set(releasedOperationIds).count == 2)
        #expect(finalSnapshot.scheduledDeadlineCount == 0)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 2
        )
        await scheduler.shutdown()
    }

    @Test("selected visible content progresses while review metadata drains")
    func contentClassProgressesIndependently() async throws {
        // Arrange
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: deadlineScheduler,
            eventSink: eventProbe.eventSink
        )
        let metadataGate = HeldStep<Void>("metadataGate", cancellation: .holdThroughCancellation)
        let contentGate = HeldStep<Void>("contentGate", cancellation: .holdThroughCancellation)
        let metadataRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "metadata")
            ) {
                try? await metadataGate.arrive(())
                return "metadata"
            }
        }
        try await metadataGate.firstArrival()
        #expect(deadlineScheduler.fireNextActiveDeadline())
        _ = await eventProbe.waitFor(.draining)
        assertBridgeGitReadTimedOut(await metadataRead.result)

        // Act
        let contentRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(
                    worktree: "worktree-a",
                    operationClass: .selectedVisibleContent,
                    key: "selected-file"
                )
            ) {
                try? await contentGate.arrive(())
                return "content"
            }
        }
        try await contentGate.firstArrival()
        let concurrentSnapshot = await scheduler.snapshot()
        contentGate.release()

        // Assert
        #expect(try await contentRead.value == "content")
        #expect(concurrentSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(concurrentSnapshot.runningCountByOperationClass[.selectedVisibleContent] == 1)
        #expect(concurrentSnapshot.occupiedSlotIds.count == 2)
        metadataGate.release()
        _ = await eventProbe.waitFor(.slotReleased, occurrence: 2)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 2
        )
        await scheduler.shutdown()
    }

    @Test("slow worktree backlog yields the next opportunity to a peer worktree")
    func worktreeFairnessPreventsBacklogMonopoly() async throws {
        // Arrange
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: BridgeGitReadManualDeadlineScheduler(),
            eventSink: eventProbe.eventSink
        )
        let firstAGate = HeldStep<Void>("firstAGate", cancellation: .holdThroughCancellation)
        let secondAGate = HeldStep<Void>("secondAGate", cancellation: .holdThroughCancellation)
        let firstBGate = HeldStep<Void>("firstBGate", cancellation: .holdThroughCancellation)
        let firstARead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "a-1")
            ) {
                try? await firstAGate.arrive(())
                return "a-1"
            }
        }
        try await firstAGate.firstArrival()
        let secondARead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "a-2")
            ) {
                try? await secondAGate.arrive(())
                return "a-2"
            }
        }
        let firstBRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-b", key: "b-1")
            ) {
                try? await firstBGate.arrive(())
                return "b-1"
            }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 3)

        // Act
        firstAGate.release()
        let secondStart = await eventProbe.waitFor(.started, occurrence: 2)

        // Assert
        #expect(secondStart.worktreeKey == BridgeGitReadWorktreeKey(token: "worktree-b"))
        if secondStart.worktreeKey == BridgeGitReadWorktreeKey(token: "worktree-b") {
            firstBGate.release()
            try await secondAGate.firstArrival()
            secondAGate.release()
        } else {
            secondAGate.release()
            try await firstBGate.firstArrival()
            firstBGate.release()
        }
        #expect(try await firstARead.value == "a-1")
        #expect(try await secondARead.value == "a-2")
        #expect(try await firstBRead.value == "b-1")
        _ = await eventProbe.waitFor(.slotReleased, occurrence: 3)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 3
        )
        await scheduler.shutdown()
    }

    @Test("caller cancellation keeps a started operation draining until true return")
    func cancellationRetainsPhysicalCustody() async throws {
        // Arrange
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: BridgeGitReadManualDeadlineScheduler(),
            eventSink: eventProbe.eventSink
        )
        let operationGate = HeldStep<Void>("operationGate", cancellation: .holdThroughCancellation)
        let readTask = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "cancelled")
            ) {
                try? await operationGate.arrive(())
                return "late"
            }
        }
        try await operationGate.firstArrival()
        let start = await eventProbe.waitFor(.started)

        // Act
        readTask.cancel()
        _ = await eventProbe.waitFor(.draining)
        let cancelledResult = await readTask.result
        let drainingSnapshot = await scheduler.snapshot()

        // Assert
        assertBridgeGitReadCancelled(cancelledResult)
        #expect(drainingSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(
            eventProbe.events.contains {
                $0.kind == .slotReleased && $0.operationId == start.operationId
            } == false
        )
        operationGate.release()
        _ = await eventProbe.waitFor(.slotReleased)
        let releasedSnapshot = await scheduler.snapshot()
        #expect(
            eventProbe.events.count {
                $0.kind == .slotReleased && $0.operationId == start.operationId
            } == 1
        )
        #expect(releasedSnapshot.activeOperationIds.isEmpty)
        #expect(releasedSnapshot.occupiedSlotIds.isEmpty)
        #expect(releasedSnapshot.logicalWaiterCount == 0)
        #expect(releasedSnapshot.scheduledDeadlineCount == 0)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 1
        )
        await scheduler.shutdown()
    }

    @Test("queued operation never starts after its last waiter cancels")
    func emptyQueuedOperationIsRemovedBeforeAdmission() async throws {
        // Arrange
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: BridgeGitReadManualDeadlineScheduler(),
            eventSink: eventProbe.eventSink
        )
        let runningGate = HeldStep<Void>("runningGate", cancellation: .holdThroughCancellation)
        let queuedGate = HeldStep<Void>("queuedGate", cancellation: .holdThroughCancellation)
        let runningRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "running")
            ) {
                try? await runningGate.arrive(())
                return "running"
            }
        }
        try await runningGate.firstArrival()
        let queuedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-b", key: "queued")
            ) {
                try? await queuedGate.arrive(())
                return "must-not-start"
            }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 2)

        // Act
        queuedRead.cancel()
        _ = await eventProbe.waitFor(.logicalCancellation)
        let beforeReleaseSnapshot = await scheduler.snapshot()
        runningGate.release()
        #expect(try await runningRead.value == "running")
        assertBridgeGitReadCancelled(await queuedRead.result)
        _ = await eventProbe.waitFor(.slotReleased)

        // Assert
        #expect(beforeReleaseSnapshot.queuedCountByOperationClass[.reviewMetadata] == nil)
        #expect(queuedGate.recordedArrivals.isEmpty)
        #expect(eventProbe.events.filter { $0.kind == .started }.count == 1)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 1
        )
        await scheduler.shutdown()
    }

    @Test("live duplicate pane rank reprioritizes queued worktrees")
    func liveDuplicatePaneRankChangesQueuedSelection() async throws {
        // Arrange
        let eventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: BridgeGitReadManualDeadlineScheduler(),
            eventSink: eventProbe.eventSink
        )
        let blockerGate = HeldStep<Void>("blockerGate", cancellation: .holdThroughCancellation)
        let firstQueuedGate = HeldStep<Void>("firstQueuedGate", cancellation: .holdThroughCancellation)
        let promotedGate = HeldStep<Void>("promotedGate", cancellation: .holdThroughCancellation)
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "pane-a"),
            worktreeKey: BridgeGitReadWorktreeKey(token: "worktree-a"),
            rank: .loadedHidden
        )
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "pane-b"),
            worktreeKey: BridgeGitReadWorktreeKey(token: "worktree-b"),
            rank: .loadedHidden
        )
        let blockerRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-blocker", key: "blocker")
            ) {
                try? await blockerGate.arrive(())
                return "blocker"
            }
        }
        try await blockerGate.firstArrival()
        let firstQueuedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "first")
            ) {
                try? await firstQueuedGate.arrive(())
                return "first"
            }
        }
        let promotedRead = Task {
            try await scheduler.read(
                request: makeBridgeGitReadRequest(worktree: "worktree-b", key: "promoted")
            ) {
                try? await promotedGate.arrive(())
                return "promoted"
            }
        }
        _ = await eventProbe.waitFor(.queued, occurrence: 3)

        // Act
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "pane-b-duplicate"),
            worktreeKey: BridgeGitReadWorktreeKey(token: "worktree-b"),
            rank: .foreground
        )
        blockerGate.release()
        let promotedStart = await eventProbe.waitFor(.started, occurrence: 2)

        // Assert
        #expect(promotedStart.worktreeKey == BridgeGitReadWorktreeKey(token: "worktree-b"))
        if promotedStart.worktreeKey == BridgeGitReadWorktreeKey(token: "worktree-b") {
            promotedGate.release()
            try await firstQueuedGate.firstArrival()
            firstQueuedGate.release()
        } else {
            firstQueuedGate.release()
            try await promotedGate.firstArrival()
            promotedGate.release()
        }
        #expect(try await blockerRead.value == "blocker")
        #expect(try await firstQueuedRead.value == "first")
        #expect(try await promotedRead.value == "promoted")
        _ = await eventProbe.waitFor(.slotReleased, occurrence: 3)
        await assertBridgeGitReadSchedulerDrained(
            scheduler,
            eventProbe: eventProbe,
            expectedSlotReleaseCount: 3
        )
        await scheduler.shutdown()
    }

    @Test("shutdown clears activity fairness state and rejects late activity")
    func shutdownClearsActivityFairnessStateAndRejectsLateActivity() async throws {
        // Arrange
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(),
            deadlineScheduler: BridgeGitReadManualDeadlineScheduler()
        )
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "pane-a"),
            worktreeKey: BridgeGitReadWorktreeKey(token: "worktree-a"),
            rank: .foreground
        )
        let value: String = try await scheduler.read(
            request: makeBridgeGitReadRequest(worktree: "worktree-a", key: "completed")
        ) {
            "completed"
        }
        let activeSnapshot = await scheduler.snapshot()

        // Act
        await scheduler.shutdown()
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "late-pane"),
            worktreeKey: BridgeGitReadWorktreeKey(token: "late-worktree"),
            rank: .foreground
        )
        let closedSnapshot = await scheduler.snapshot()

        // Assert
        #expect(value == "completed")
        #expect(activeSnapshot.paneActivityCount == 1)
        #expect(activeSnapshot.fairnessHistoryCount == 1)
        #expect(closedSnapshot.lifecycle == .closed)
        #expect(closedSnapshot.paneActivityCount == 0)
        #expect(closedSnapshot.fairnessHistoryCount == 0)
    }
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

private func assertBridgeGitReadSchedulerDrained(
    _ scheduler: BridgeGitReadScheduler,
    eventProbe: BridgeGitReadSchedulerEventProbe,
    expectedSlotReleaseCount: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let snapshot = await scheduler.snapshot()
    let releasedOperationIds = eventProbe.events
        .filter { $0.kind == .slotReleased }
        .map(\.operationId)
    #expect(
        releasedOperationIds.count == expectedSlotReleaseCount,
        sourceLocation: sourceLocation
    )
    #expect(
        Set(releasedOperationIds).count == expectedSlotReleaseCount,
        sourceLocation: sourceLocation
    )
    #expect(snapshot.activeOperationIds.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.occupiedSlotIds.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.logicalWaiterCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.scheduledDeadlineCount == 0, sourceLocation: sourceLocation)
}
