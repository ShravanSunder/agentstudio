import Foundation

/// One scheduled unit of metadata production. The scheduler never learns
/// protocol semantics: `protocolId` and `generation` are identity and
/// stale-drop scope, never priority.
struct BridgeMetadataLaneJob: Sendable {
    let protocolId: String
    let generation: Int
    let lane: BridgeDemandLane
    /// Emission work: reserve the protocol sequence, encode, and deliver.
    /// Jobs execute serially on the drain loop, so sequence order equals
    /// delivery order by construction. Returning false signals a transport
    /// failure: the scheduler closes the protocol gate and retains the job
    /// at the front of its lane for retry when the gate reopens.
    let work: @MainActor @Sendable () async -> Bool
}

/// Queue-wait and drop facts emitted by the scheduler. Enqueue-to-dequeue
/// only; a request-to-delivered-frame span must never be reported here.
protocol BridgeMetadataLaneSchedulerTelemetry: Sendable {
    func recordQueueWait(
        lane: BridgeDemandLane,
        protocolId: String,
        waitMilliseconds: Double,
        queueDepth: Int
    ) async
    func recordStaleDrop(lane: BridgeDemandLane, protocolId: String, droppedCount: Int) async
}

/// Test seam: gates each idle-lane job so contention proofs can hold idle
/// continuation mid-flight deterministically. Production passes nil.
/// This is an ordinary constructor dependency, not a debug hook.
actor BridgeMetadataLaneSchedulerIdleGate {
    private var pendingSteps = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var parkedJobObservers: [CheckedContinuation<Void, Never>] = []

    func allowSteps(_ count: Int) {
        pendingSteps += count
        while pendingSteps > 0, !waiters.isEmpty {
            pendingSteps -= 1
            waiters.removeFirst().resume()
        }
    }

    func waitForStep() async {
        if pendingSteps > 0 {
            pendingSteps -= 1
            return
        }
        while !parkedJobObservers.isEmpty {
            parkedJobObservers.removeFirst().resume()
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Bounded event wait until an idle job is parked at the gate, so tests
    /// can interleave higher-lane enqueues against mid-flight idle work
    /// deterministically (no polling, no sleeps).
    func waitForParkedIdleJob() async {
        if !waiters.isEmpty {
            return
        }
        await withCheckedContinuation { continuation in
            parkedJobObservers.append(continuation)
        }
    }
}

/// Generic per-pane lane scheduler for native metadata production
/// (spec: performance-demand-lanes.md, Native Metadata Production
/// Scheduler). It is the single ordering authority for frame emission:
/// per-lane FIFO queues with strict priority, per-protocol dispatch gates,
/// an idle no-starvation budget, and enqueue-to-dequeue queue-wait
/// instrumentation. It owns no protocol semantics and no frame contents.
actor BridgeMetadataLaneScheduler {
    private struct QueuedJob {
        let job: BridgeMetadataLaneJob
        let enqueuedAt: ContinuousClock.Instant
    }

    private static let lanePriority: [BridgeDemandLane] = [
        .foreground, .active, .visible, .nearby, .speculative, .idle,
    ]

    private let clock: ContinuousClock
    private let idleNoStarvationBudget: Int
    private let idleGate: BridgeMetadataLaneSchedulerIdleGate?
    private var telemetry: (any BridgeMetadataLaneSchedulerTelemetry)?

    private var queuesByLane: [BridgeDemandLane: [QueuedJob]] = [:]
    private var openProtocolIds = Set<String>()
    private var currentGenerationByProtocol: [String: Int] = [:]
    private var drainTask: Task<Void, Never>?
    private var higherLaneJobsSinceIdleService = 0
    private(set) var drainedJobCount = 0
    private(set) var staleDroppedJobCount = 0

    init(
        clock: ContinuousClock = ContinuousClock(),
        idleNoStarvationBudget: Int = AppPolicies.Bridge.metadataIdleNoStarvationBudget,
        idleGate: BridgeMetadataLaneSchedulerIdleGate? = nil,
        telemetry: (any BridgeMetadataLaneSchedulerTelemetry)? = nil
    ) {
        self.clock = clock
        self.idleNoStarvationBudget = max(1, idleNoStarvationBudget)
        self.idleGate = idleGate
        self.telemetry = telemetry
    }

    var queuedJobCount: Int {
        queuesByLane.values.reduce(0) { $0 + $1.count }
    }

    /// Late telemetry wiring for owners whose recorder is not available at
    /// scheduler construction time.
    func configureTelemetry(_ telemetry: any BridgeMetadataLaneSchedulerTelemetry) {
        self.telemetry = telemetry
    }

    /// Accepts the current generation for a protocol; queued jobs bound to
    /// any other generation are dropped and counted.
    func acceptGeneration(_ generation: Int, protocolId: String) async {
        currentGenerationByProtocol[protocolId] = generation
        await dropStaleJobs(protocolId: protocolId)
    }

    /// Opens the dispatch gate for a protocol (intake ready). Closed-gate
    /// jobs hold in their lanes without blocking other protocols.
    func openGate(protocolId: String) {
        openProtocolIds.insert(protocolId)
        scheduleDrain()
    }

    func closeGate(protocolId: String) {
        openProtocolIds.remove(protocolId)
    }

    func enqueue(_ job: BridgeMetadataLaneJob) {
        guard currentGenerationByProtocol[job.protocolId] == job.generation else {
            staleDroppedJobCount += 1
            return
        }
        queuesByLane[job.lane, default: []].append(
            QueuedJob(job: job, enqueuedAt: clock.now)
        )
        scheduleDrain()
    }

    /// Waits for the scheduler to become fully idle (no queued dispatchable
    /// jobs and no active drain). Bounded event wait for tests and teardown;
    /// the drain's own completion clears `drainTask` on the actor, and the
    /// loop re-checks in case a new drain was scheduled meanwhile.
    func waitUntilDrained() async {
        while let task = drainTask {
            await task.value
        }
    }

    private func scheduleDrain() {
        guard drainTask == nil else {
            return
        }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        defer { drainTask = nil }
        while let dequeued = dequeueNextDispatchableJob() {
            if dequeued.job.lane == .idle, let idleGate {
                await idleGate.waitForStep()
            }
            guard currentGenerationByProtocol[dequeued.job.protocolId] == dequeued.job.generation
            else {
                staleDroppedJobCount += 1
                continue
            }
            let waitMilliseconds = Self.milliseconds(
                from: dequeued.enqueuedAt.duration(to: clock.now)
            )
            await telemetry?.recordQueueWait(
                lane: dequeued.job.lane,
                protocolId: dequeued.job.protocolId,
                waitMilliseconds: waitMilliseconds,
                queueDepth: queuedJobCount
            )
            let delivered = await dequeued.job.work()
            guard delivered else {
                // Transport failure: retain the job at the front of its lane
                // and close the gate; reopening the gate retries in order.
                closeGate(protocolId: dequeued.job.protocolId)
                queuesByLane[dequeued.job.lane, default: []].insert(dequeued, at: 0)
                continue
            }
            drainedJobCount += 1
            if dequeued.job.lane == .idle {
                higherLaneJobsSinceIdleService = 0
            } else {
                higherLaneJobsSinceIdleService += 1
            }
        }
    }

    /// Strict lane priority with an idle no-starvation budget: after N
    /// higher-lane jobs drain while idle work waits, the next dispatch is
    /// an idle batch even if higher-lane jobs are queued. A queued
    /// higher-lane job therefore waits at most one bounded idle batch.
    private func dequeueNextDispatchableJob() -> QueuedJob? {
        let idleHasDispatchableWork = hasDispatchableJob(in: .idle)
        if idleHasDispatchableWork, higherLaneJobsSinceIdleService >= idleNoStarvationBudget {
            if let idleJob = removeFirstDispatchableJob(in: .idle) {
                return idleJob
            }
        }
        for lane in Self.lanePriority {
            if let job = removeFirstDispatchableJob(in: lane) {
                return job
            }
        }
        return nil
    }

    private func hasDispatchableJob(in lane: BridgeDemandLane) -> Bool {
        queuesByLane[lane]?.contains { openProtocolIds.contains($0.job.protocolId) } ?? false
    }

    private func removeFirstDispatchableJob(in lane: BridgeDemandLane) -> QueuedJob? {
        guard var queue = queuesByLane[lane], !queue.isEmpty else {
            return nil
        }
        guard
            let index = queue.firstIndex(where: { openProtocolIds.contains($0.job.protocolId) })
        else {
            return nil
        }
        let dequeued = queue.remove(at: index)
        queuesByLane[lane] = queue
        return dequeued
    }

    private func dropStaleJobs(protocolId: String) async {
        for (lane, queue) in queuesByLane {
            let currentGeneration = currentGenerationByProtocol[protocolId]
            let retained = queue.filter { queued in
                queued.job.protocolId != protocolId
                    || queued.job.generation == currentGeneration
            }
            let droppedCount = queue.count - retained.count
            if droppedCount > 0 {
                staleDroppedJobCount += droppedCount
                queuesByLane[lane] = retained
                await telemetry?.recordStaleDrop(
                    lane: lane,
                    protocolId: protocolId,
                    droppedCount: droppedCount
                )
            }
        }
    }

    private static func milliseconds(from duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
