import Foundation

enum TerminalAccumulatorDrainClass: String, Equatable, Sendable {
    case immediate
    case titleWindow = "title_window"
    case exactBarrier = "exact_barrier"
}

struct TerminalAccumulatorDrainPerformanceSnapshot: Equatable, Sendable {
    let drainClass: TerminalAccumulatorDrainClass
    let offeredCount: UInt64
    let replacedCount: UInt64
    let equalSuppressedCount: UInt64
    let scheduledDrainCount: UInt64
    let followUpDrainCount: UInt64
    let mainActorTaskCount: UInt64
    let activityAggregateCount: UInt64
    let retainedEntryCount: UInt64
    let retainedSizeBytes: UInt64
}

struct TerminalCompactApplyPerformanceSnapshot: Equatable, Sendable {
    let equalWriteSuppressedCount: UInt64
    let activityProjectionRoundTrip: TerminalActivityProjectionRoundTripPerformance
}

enum TerminalActivityProjectionRoundTripPerformance: Equatable, Sendable {
    case notSubmitted
    case completed(Duration)
}

struct FilesystemEffectPerformanceSnapshot: Equatable, Sendable {
    let fullReconciliationRequestCount: UInt64
    let affectedKeyRequestCount: UInt64
}

struct TraceIdentityPerformanceSnapshot: Equatable, Sendable {
    let refreshRequestCount: UInt64
    let coalescedRequestCount: UInt64
    let fleetCaptureCount: UInt64
    let equalSnapshotSuppressedCount: UInt64
}

final class AgentStudioPerformanceTraceRecorder: @unchecked Sendable {
    struct TopologyLookupFact: Hashable, Sendable {
        let normalizedCWD: String
        let worktreePathIndexGeneration: UInt64
        let repoId: UUID?
        let worktreeId: UUID?
    }

    enum Event: String, Sendable {
        case atomDerived = "performance.atom.derived"
        case atomMutation = "performance.atom.mutation"
        case atomRead = "performance.atom.read"
        case bridgeGitReadScheduler = "performance.bridge.git_read_scheduler"
        case bridgeWorktreeProductConstruction = "performance.bridge.worktree_product_construction"
        case commandBarFilter = "performance.commandbar.filter"
        case commandBarItems = "performance.commandbar.items"
        case coordinatorWrite = "performance.coordinator.write"
        case filesystemEffectSnapshot = "performance.filesystem.effect_snapshot"
        case filesystemLogicalDebt = "performance.filesystem.logical_debt"
        case gitAdmission = "performance.git.admission"
        case gitBackoff = "performance.git.backoff"
        case gitEventPosted = "performance.git.event_posted"
        case gitPathQuarantine = "performance.git.path_quarantine"
        case gitLogicalDebt = "performance.git.logical_debt"
        case gitSnapshotDedup = "performance.git.snapshot_dedup"
        case gitStatusComputed = "performance.git.status"
        case gitStatusUnavailable = "performance.git.status_unavailable"
        case gitSuppressedInputSkipped = "performance.git.suppressed_input_skipped"
        case gitTick = "performance.git.tick"
        case managementLayerAppKitState = "performance.management_layer.appkit_state"
        case managementLayerCommand = "performance.management_layer.command"
        case paneActionExecution = "performance.pane_action.execution"
        case paneTabLayout = "performance.pane_tab.layout"
        case paneViewRestore = "performance.pane_view.restore"
        case paneViewRestoreVisible = "performance.pane_view.restore_visible"
        case repoAndWorktreeLookup = "performance.topology.repo_and_worktree"
        case processMallocZone = "performance.process.malloc_zone"
        case runtimeDeliverySnapshot = "performance.runtime_delivery.snapshot"
        case sidebarFilterInput = "performance.sidebar.filter_input"
        case sidebarProjection = "performance.sidebar.projection"
        case sidebarRowIndex = "performance.sidebar.row_index"
        case sidebarResize = "performance.sidebar.resize"
        case sidebarToggle = "performance.sidebar.toggle"
        case tabBarRefresh = "performance.tabbar.refresh"
        case terminalAccumulatorDrain = "performance.terminal.accumulator_drain"
        case terminalCompactApply = "performance.terminal.compact_apply"
        case terminalForceGeometrySync = "performance.terminal.force_geometry_sync"
        case terminalGeometrySync = "performance.terminal.geometry_sync"
        case terminalMountLayout = "performance.terminal.mount_layout"
        case terminalSurfaceSizeDidChange = "performance.terminal.surface_size"
        case traceIdentitySnapshot = "performance.trace_identity.snapshot"
    }

    private let traceRuntime: AgentStudioTraceRuntime?
    private let eventQueue: AgentStudioTraceEventQueue?
    private let lock = NSLock()
    private var topologyLookupAdmission = TopologyLookupTraceAdmission()
    private let processMemorySampler: AgentStudioProcessMemorySampler?
    private let runtimeDeliveryPerformanceReporter: RuntimeDeliveryPerformanceReporter?

    init(
        traceRuntime: AgentStudioTraceRuntime?,
        runtimeDeliveryPerformanceReporter: RuntimeDeliveryPerformanceReporter? = nil,
        processMemorySampleWait: @escaping AgentStudioProcessMemorySampler.WaitForNextSample =
            AgentStudioProcessMemorySampler.waitOneSecond
    ) {
        self.traceRuntime = traceRuntime
        if let traceRuntime, traceRuntime.isEnabled(.performance) {
            runtimeDeliveryPerformanceReporter?.enable()
            self.runtimeDeliveryPerformanceReporter = runtimeDeliveryPerformanceReporter
            let eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
            self.eventQueue = eventQueue
            let processMemorySampler = AgentStudioProcessMemorySampler(
                waitForNextSample: processMemorySampleWait
            ) { snapshot in
                eventQueue.record(
                    tag: .performance,
                    body: Event.processMallocZone.rawValue,
                    eventTimeUnixNano: traceRuntime.timestampUnixNano(),
                    attributes: snapshot.traceAttributes
                )
                if let runtimeDeliverySnapshot = runtimeDeliveryPerformanceReporter?.snapshot() {
                    eventQueue.record(
                        tag: .performance,
                        body: Event.runtimeDeliverySnapshot.rawValue,
                        eventTimeUnixNano: traceRuntime.timestampUnixNano(),
                        attributes: runtimeDeliverySnapshot.traceAttributes
                    )
                }
            }
            self.processMemorySampler = processMemorySampler
            processMemorySampler.start()
        } else {
            self.eventQueue = nil
            self.processMemorySampler = nil
            self.runtimeDeliveryPerformanceReporter = nil
        }
    }

    deinit {
        processMemorySampler?.cancel()
        runtimeDeliveryPerformanceReporter?.disable()
    }

    var isEnabled: Bool {
        eventQueue != nil
    }

    func record(
        _ event: Event,
        attributes: [String: AgentStudioTraceValue] = [:]
    ) {
        guard let traceRuntime, traceRuntime.isEnabled(.performance), let eventQueue else { return }
        eventQueue.record(
            tag: .performance,
            body: event.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }

    func recordDuration(
        _ event: Event,
        duration: Duration,
        attributes: [String: AgentStudioTraceValue] = [:]
    ) {
        var mergedAttributes = attributes
        mergedAttributes["agentstudio.performance.elapsed_ms"] = .double(Self.milliseconds(from: duration))
        record(event, attributes: mergedAttributes)
    }

    func recordRepoAndWorktreeLookup(
        duration: Duration,
        indexCount: Int,
        hasMatch: Bool,
        fact: TopologyLookupFact
    ) {
        guard shouldRecordTopologyLookup(fact) else { return }
        recordDuration(
            .repoAndWorktreeLookup,
            duration: duration,
            attributes: [
                "agentstudio.performance.topology.index.count": .int(indexCount),
                "agentstudio.performance.topology.has_match": .bool(hasMatch),
            ]
        )
    }

    func recordTerminalAccumulatorDrain(
        _ snapshot: TerminalAccumulatorDrainPerformanceSnapshot,
        queueAge: Duration
    ) {
        recordDuration(
            .terminalAccumulatorDrain,
            duration: queueAge,
            attributes: [
                "agentstudio.performance.terminal.accumulator.drain.class": .string(
                    snapshot.drainClass.rawValue
                ),
                "agentstudio.performance.terminal.accumulator.offered.count": Self.traceInteger(
                    snapshot.offeredCount),
                "agentstudio.performance.terminal.accumulator.replaced.count": Self.traceInteger(
                    snapshot.replacedCount),
                "agentstudio.performance.terminal.accumulator.equal_suppressed.count": Self.traceInteger(
                    snapshot.equalSuppressedCount),
                "agentstudio.performance.terminal.accumulator.scheduled_drain.count": Self.traceInteger(
                    snapshot.scheduledDrainCount),
                "agentstudio.performance.terminal.accumulator.follow_up_drain.count": Self.traceInteger(
                    snapshot.followUpDrainCount),
                "agentstudio.performance.terminal.accumulator.mainactor_task.count": Self.traceInteger(
                    snapshot.mainActorTaskCount),
                "agentstudio.performance.terminal.activity_aggregate.count": Self.traceInteger(
                    snapshot.activityAggregateCount),
                "agentstudio.performance.terminal.accumulator.retained_entry.count": Self.traceInteger(
                    snapshot.retainedEntryCount),
                "agentstudio.performance.terminal.accumulator.retained_size_bytes": Self.traceInteger(
                    snapshot.retainedSizeBytes),
            ]
        )
    }

    func recordTerminalCompactApply(
        _ snapshot: TerminalCompactApplyPerformanceSnapshot,
        serviceTime: Duration
    ) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.terminal.equal_write_suppressed.count": Self.traceInteger(
                snapshot.equalWriteSuppressedCount)
        ]
        switch snapshot.activityProjectionRoundTrip {
        case .notSubmitted:
            attributes["agentstudio.performance.terminal.activity_projection.submitted"] = .bool(false)
        case .completed(let duration):
            attributes["agentstudio.performance.terminal.activity_projection.submitted"] = .bool(true)
            attributes["agentstudio.performance.terminal.activity_projection.round_trip_ms"] = .double(
                Self.milliseconds(from: duration)
            )
        }
        recordDuration(
            .terminalCompactApply,
            duration: serviceTime,
            attributes: attributes
        )
    }

    func recordFilesystemEffectSnapshot(_ snapshot: FilesystemEffectPerformanceSnapshot) {
        record(
            .filesystemEffectSnapshot,
            attributes: [
                "agentstudio.performance.filesystem.full_reconciliation_request.count": Self.traceInteger(
                    snapshot.fullReconciliationRequestCount),
                "agentstudio.performance.filesystem.affected_key_request.count": Self.traceInteger(
                    snapshot.affectedKeyRequestCount),
            ]
        )
    }

    func recordTraceIdentitySnapshot(_ snapshot: TraceIdentityPerformanceSnapshot) {
        record(
            .traceIdentitySnapshot,
            attributes: [
                "agentstudio.performance.trace_identity.refresh_request.count": Self.traceInteger(
                    snapshot.refreshRequestCount),
                "agentstudio.performance.trace_identity.coalesced_request.count": Self.traceInteger(
                    snapshot.coalescedRequestCount),
                "agentstudio.performance.trace_identity.fleet_capture.count": Self.traceInteger(
                    snapshot.fleetCaptureCount),
                "agentstudio.performance.trace_identity.equal_snapshot_suppressed.count": Self.traceInteger(
                    snapshot.equalSnapshotSuppressedCount),
            ]
        )
    }

    func measure<T>(
        _ event: Event,
        attributes: [String: AgentStudioTraceValue] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try operation()
        }

        let clock = ContinuousClock()
        let start = clock.now
        let result = try operation()
        recordDuration(
            event,
            duration: start.duration(to: clock.now),
            attributes: attributes
        )
        return result
    }

    func drain() async throws {
        await processMemorySampler?.stop()
        runtimeDeliveryPerformanceReporter?.disable()
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        let secondsMilliseconds = Double(components.seconds) * 1000
        let attosecondsMilliseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMilliseconds + attosecondsMilliseconds
    }

    private func shouldRecordTopologyLookup(_ fact: TopologyLookupFact) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return topologyLookupAdmission.admit(
            fact,
            now: ContinuousClock().now,
            window: AppPolicies.Diagnostics.topologyLookupTraceAdmissionWindow,
            limit: AppPolicies.Diagnostics.topologyLookupTraceAdmissionLimit
        )
    }

    private static func traceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(Int(clamping: value))
    }
}

private struct TopologyLookupTraceAdmission {
    private var windowStart: ContinuousClock.Instant?
    private var admittedInWindow = 0
    private var emittedFactGeneration: UInt64?
    private var emittedFacts: Set<AgentStudioPerformanceTraceRecorder.TopologyLookupFact> = []

    mutating func admit(
        _ fact: AgentStudioPerformanceTraceRecorder.TopologyLookupFact,
        now: ContinuousClock.Instant,
        window: Duration,
        limit: Int
    ) -> Bool {
        resetDeduplicationIfNeeded(for: fact)
        guard !emittedFacts.contains(fact) else { return false }
        resetWindowIfNeeded(now: now, window: window)
        guard admittedInWindow < limit else { return false }
        admittedInWindow += 1
        emittedFacts.insert(fact)
        return true
    }

    private mutating func resetDeduplicationIfNeeded(
        for fact: AgentStudioPerformanceTraceRecorder.TopologyLookupFact
    ) {
        guard emittedFactGeneration != fact.worktreePathIndexGeneration else { return }
        emittedFactGeneration = fact.worktreePathIndexGeneration
        emittedFacts.removeAll(keepingCapacity: true)
    }

    private mutating func resetWindowIfNeeded(now: ContinuousClock.Instant, window: Duration) {
        guard let windowStart else {
            self.windowStart = now
            admittedInWindow = 0
            return
        }
        guard windowStart.duration(to: now) >= window else { return }
        self.windowStart = now
        admittedInWindow = 0
    }
}
