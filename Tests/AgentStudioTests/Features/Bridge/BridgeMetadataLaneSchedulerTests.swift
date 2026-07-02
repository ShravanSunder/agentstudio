import Foundation
import Testing

@testable import AgentStudio

@MainActor
final class SchedulerExecutionOrderRecorder {
    private(set) var executedLabels: [String] = []

    func record(_ label: String) {
        executedLabels.append(label)
    }
}

actor SchedulerFailFirstAttemptFlag {
    private var hasFailed = false

    func consumeFailure() -> Bool {
        guard !hasFailed else { return false }
        hasFailed = true
        return true
    }
}

actor SchedulerTelemetrySpy: BridgeMetadataLaneSchedulerTelemetry {
    struct QueueWaitSample: Sendable {
        let lane: BridgeDemandLane
        let protocolId: String
        let waitMilliseconds: Double
        let queueDepth: Int
    }

    private(set) var queueWaitSamples: [QueueWaitSample] = []
    private(set) var staleDropCounts: [BridgeDemandLane: Int] = [:]

    func recordQueueWait(
        lane: BridgeDemandLane,
        protocolId: String,
        waitMilliseconds: Double,
        queueDepth: Int
    ) {
        queueWaitSamples.append(
            QueueWaitSample(
                lane: lane,
                protocolId: protocolId,
                waitMilliseconds: waitMilliseconds,
                queueDepth: queueDepth
            )
        )
    }

    func recordStaleDrop(lane: BridgeDemandLane, protocolId: String, droppedCount: Int) {
        staleDropCounts[lane, default: 0] += droppedCount
    }
}

@Suite("BridgeMetadataLaneScheduler contract")
struct BridgeMetadataLaneSchedulerTests {
    private func makeJob(
        _ label: String,
        lane: BridgeDemandLane,
        protocolId: String = "worktree-file",
        generation: Int = 1,
        recorder: SchedulerExecutionOrderRecorder
    ) -> BridgeMetadataLaneJob {
        BridgeMetadataLaneJob(
            protocolId: protocolId,
            generation: generation,
            lane: lane
        ) { @MainActor in
            recorder.record(label)
            return true
        }
    }

    @Test("a failed delivery closes the gate, retains the job, and retries on reopen")
    func failedDeliveryClosesGateRetainsJobAndRetriesOnReopen() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let failFirstAttempt = SchedulerFailFirstAttemptFlag()
        let scheduler = BridgeMetadataLaneScheduler()
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.enqueue(
            BridgeMetadataLaneJob(
                protocolId: "worktree-file",
                generation: 1,
                lane: .visible
            ) { @MainActor in
                if await failFirstAttempt.consumeFailure() {
                    recorder.record("failed-attempt")
                    return false
                }
                recorder.record("delivered")
                return true
            }
        )
        await scheduler.enqueue(makeJob("follower", lane: .visible, recorder: recorder))
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()
        // The failure closed the gate: both jobs are retained, in order.
        #expect(await MainActor.run { recorder.executedLabels } == ["failed-attempt"])
        #expect(await scheduler.queuedJobCount == 2)

        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()
        #expect(
            await MainActor.run { recorder.executedLabels }
                == ["failed-attempt", "delivered", "follower"]
        )
    }

    @Test("strict lane priority dispatches foreground before idle regardless of arrival order")
    func strictLanePriorityDispatchesForegroundBeforeIdle() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let scheduler = BridgeMetadataLaneScheduler(idleNoStarvationBudget: 100)
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.enqueue(makeJob("idle-1", lane: .idle, recorder: recorder))
        await scheduler.enqueue(makeJob("idle-2", lane: .idle, recorder: recorder))
        await scheduler.enqueue(makeJob("visible-1", lane: .visible, recorder: recorder))
        await scheduler.enqueue(makeJob("foreground-1", lane: .foreground, recorder: recorder))
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()

        let executed = await MainActor.run { recorder.executedLabels }
        #expect(executed == ["foreground-1", "visible-1", "idle-1", "idle-2"])
    }

    @Test("review foreground work drains before worktree-file idle continuation")
    func reviewForegroundDrainsBeforeWorktreeFileIdleContinuation() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let scheduler = BridgeMetadataLaneScheduler(idleNoStarvationBudget: 100)
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.acceptGeneration(1, protocolId: "review")
        await scheduler.enqueue(makeJob("worktree-idle", lane: .idle, recorder: recorder))
        await scheduler.enqueue(
            makeJob("review-foreground", lane: .foreground, protocolId: "review", recorder: recorder)
        )
        await scheduler.openGate(protocolId: "review")
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()

        let executed = await MainActor.run { recorder.executedLabels }
        #expect(executed == ["review-foreground", "worktree-idle"])
    }

    @Test("within a lane jobs dispatch in arrival order across protocols")
    func withinLaneJobsDispatchInArrivalOrder() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let scheduler = BridgeMetadataLaneScheduler()
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.acceptGeneration(1, protocolId: "review")
        await scheduler.enqueue(makeJob("wf-1", lane: .visible, recorder: recorder))
        await scheduler.enqueue(
            makeJob("review-1", lane: .visible, protocolId: "review", recorder: recorder)
        )
        await scheduler.enqueue(makeJob("wf-2", lane: .visible, recorder: recorder))
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.openGate(protocolId: "review")
        await scheduler.waitUntilDrained()

        let executed = await MainActor.run { recorder.executedLabels }
        #expect(executed == ["wf-1", "review-1", "wf-2"])
    }

    @Test("idle no-starvation budget services one idle batch per N higher-lane jobs")
    func idleNoStarvationBudgetServicesIdleBatches() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let scheduler = BridgeMetadataLaneScheduler(idleNoStarvationBudget: 2)
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        for index in 0..<2 {
            await scheduler.enqueue(makeJob("idle-\(index)", lane: .idle, recorder: recorder))
        }
        for index in 0..<6 {
            await scheduler.enqueue(
                makeJob("foreground-\(index)", lane: .foreground, recorder: recorder)
            )
        }
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()

        let executed = await MainActor.run { recorder.executedLabels }
        // Budget of 2: after every 2 higher-lane jobs, one idle batch runs,
        // so idle work progresses while foreground pressure continues.
        #expect(
            executed == [
                "foreground-0", "foreground-1", "idle-0",
                "foreground-2", "foreground-3", "idle-1",
                "foreground-4", "foreground-5",
            ])
    }

    @Test("a queued higher-lane job waits at most one gated idle batch")
    func higherLaneJobWaitsAtMostOneIdleBatch() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let idleGate = BridgeMetadataLaneSchedulerIdleGate()
        let scheduler = BridgeMetadataLaneScheduler(idleGate: idleGate)
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.enqueue(makeJob("idle-0", lane: .idle, recorder: recorder))
        await scheduler.enqueue(makeJob("idle-1", lane: .idle, recorder: recorder))
        await scheduler.openGate(protocolId: "worktree-file")
        // Wait until the drain is actually holding idle-0 at the gate
        // (mid-flight idle work), then inject the higher-lane job.
        await idleGate.waitForParkedIdleJob()
        await scheduler.enqueue(makeJob("foreground-0", lane: .foreground, recorder: recorder))
        await idleGate.allowSteps(2)
        await scheduler.waitUntilDrained()

        let executed = await MainActor.run { recorder.executedLabels }
        // foreground-0 preempts idle-1 but waits behind the already-dequeued
        // idle-0 batch: at most one bounded idle batch of wait.
        #expect(executed == ["idle-0", "foreground-0", "idle-1"])
    }

    @Test("generation bump drops queued stale jobs and rejects stale enqueues")
    func generationBumpDropsQueuedStaleJobs() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let telemetrySpy = SchedulerTelemetrySpy()
        let scheduler = BridgeMetadataLaneScheduler(telemetry: telemetrySpy)
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.enqueue(makeJob("stale-1", lane: .visible, recorder: recorder))
        await scheduler.enqueue(makeJob("stale-2", lane: .idle, recorder: recorder))
        await scheduler.acceptGeneration(2, protocolId: "worktree-file")
        await scheduler.enqueue(
            makeJob("stale-enqueue", lane: .visible, generation: 1, recorder: recorder)
        )
        await scheduler.enqueue(
            makeJob("current-1", lane: .visible, generation: 2, recorder: recorder)
        )
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()

        let executed = await MainActor.run { recorder.executedLabels }
        #expect(executed == ["current-1"])
        #expect(await scheduler.staleDroppedJobCount == 3)
        // Every stale-drop lane emits telemetry: the two queued jobs dropped
        // by the generation bump AND the rejected stale enqueue, so the
        // emitted count matches staleDroppedJobCount instead of
        // under-reporting.
        let dropCounts = await telemetrySpy.staleDropCounts
        #expect((dropCounts[.visible] ?? 0) + (dropCounts[.idle] ?? 0) == 3)
    }

    @Test("queue-wait samples are recorded per lane from enqueue to dequeue")
    func queueWaitSamplesRecordedPerLane() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let telemetrySpy = SchedulerTelemetrySpy()
        let scheduler = BridgeMetadataLaneScheduler(telemetry: telemetrySpy)
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.enqueue(makeJob("idle-0", lane: .idle, recorder: recorder))
        await scheduler.enqueue(makeJob("foreground-0", lane: .foreground, recorder: recorder))
        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()

        let samples = await telemetrySpy.queueWaitSamples
        #expect(samples.count == 2)
        #expect(samples.contains { $0.lane == .foreground })
        #expect(samples.contains { $0.lane == .idle })
        #expect(samples.allSatisfy { $0.waitMilliseconds >= 0 })
    }

    @Test("a closed protocol gate holds its jobs without blocking other protocols")
    func closedGateHoldsJobsWithoutBlockingOtherProtocols() async throws {
        let recorder = await MainActor.run { SchedulerExecutionOrderRecorder() }
        let scheduler = BridgeMetadataLaneScheduler()
        await scheduler.acceptGeneration(1, protocolId: "worktree-file")
        await scheduler.acceptGeneration(1, protocolId: "review")
        await scheduler.enqueue(makeJob("wf-held", lane: .foreground, recorder: recorder))
        await scheduler.enqueue(
            makeJob("review-1", lane: .visible, protocolId: "review", recorder: recorder)
        )
        await scheduler.openGate(protocolId: "review")
        await scheduler.waitUntilDrained()
        #expect(await MainActor.run { recorder.executedLabels } == ["review-1"])
        #expect(await scheduler.queuedJobCount == 1)

        await scheduler.openGate(protocolId: "worktree-file")
        await scheduler.waitUntilDrained()
        #expect(await MainActor.run { recorder.executedLabels } == ["review-1", "wf-held"])
    }
}
