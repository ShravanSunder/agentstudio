import Foundation

final class AgentStudioPerformanceTraceRecorder: @unchecked Sendable {
    enum Event: String, Sendable {
        case atomDerived = "performance.atom.derived"
        case atomMutation = "performance.atom.mutation"
        case atomRead = "performance.atom.read"
        case commandBarFilter = "performance.commandbar.filter"
        case commandBarItems = "performance.commandbar.items"
        case coordinatorWrite = "performance.coordinator.write"
        case gitAdmission = "performance.git.admission"
        case gitEventPosted = "performance.git.event_posted"
        case gitSnapshotDedup = "performance.git.snapshot_dedup"
        case gitStatusComputed = "performance.git.status"
        case gitStatusUnavailable = "performance.git.status_unavailable"
        case gitSuppressedInputSkipped = "performance.git.suppressed_input_skipped"
        case gitTick = "performance.git.tick"
        case managementLayerAppKitState = "performance.management_layer.appkit_state"
        case managementLayerCommand = "performance.management_layer.command"
        case mainActorHeartbeat = "performance.mainactor.heartbeat"
        case mainActorWork = "performance.mainactor.work"
        case paneActionExecution = "performance.pane_action.execution"
        case paneTabLayout = "performance.pane_tab.layout"
        case paneViewRestore = "performance.pane_view.restore"
        case paneViewRestoreVisible = "performance.pane_view.restore_visible"
        case repoAndWorktreeLookup = "performance.topology.repo_and_worktree"
        case sidebarFilterInput = "performance.sidebar.filter_input"
        case sidebarProjection = "performance.sidebar.projection"
        case sidebarRowIndex = "performance.sidebar.row_index"
        case sidebarResize = "performance.sidebar.resize"
        case sidebarToggle = "performance.sidebar.toggle"
        case tabBarRefresh = "performance.tabbar.refresh"
        case terminalForceGeometrySync = "performance.terminal.force_geometry_sync"
        case terminalGeometrySync = "performance.terminal.geometry_sync"
        case terminalMountLayout = "performance.terminal.mount_layout"
        case terminalSurfaceSizeDidChange = "performance.terminal.surface_size"
        case pipelineContraction = "performance.pipeline.contraction"
    }

    private let traceRuntime: AgentStudioTraceRuntime?
    private let eventQueue: AgentStudioTraceEventQueue?

    init(traceRuntime: AgentStudioTraceRuntime?) {
        self.traceRuntime = traceRuntime
        if let traceRuntime, traceRuntime.isEnabled(.performance) {
            self.eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            self.eventQueue = nil
        }
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

    func record(_ probe: PerformanceProbeRecord) {
        switch probe {
        case .mainActorWork(let work, let agePrecision):
            let queueAgeKey: String
            switch agePrecision {
            case .exact:
                queueAgeKey = "agentstudio.performance.mainactor.queue_age_exact_ms"
            case .pressureConservative:
                queueAgeKey = "agentstudio.performance.mainactor.queue_age_pressure_conservative_ms"
            }
            record(
                .mainActorWork,
                attributes: [
                    "agentstudio.performance.mainactor.domain": .string(work.domain.rawValue),
                    "agentstudio.performance.mainactor.operation": .string(work.operation.rawValue),
                    "agentstudio.performance.mainactor.outcome": .string(work.outcome.rawValue),
                    "agentstudio.performance.mainactor.age_precision": .string(agePrecision.rawValue),
                    queueAgeKey: .double(Double(work.queueAgeNanoseconds) / 1_000_000),
                    "agentstudio.performance.mainactor.service_ms": .double(
                        Double(work.synchronousServiceNanoseconds) / 1_000_000),
                    "agentstudio.performance.mainactor.input.count": .int(Self.intClamped(work.counts.input)),
                    "agentstudio.performance.mainactor.changed_key.count": .int(
                        Self.intClamped(work.counts.changedKey)),
                ]
            )
        case .heartbeat(let heartbeat):
            let overdueCount: UInt64
            switch heartbeat.overdue {
            case .withinBudget:
                overdueCount = 0
            case .overdue(let consecutiveCount):
                overdueCount = consecutiveCount
            }
            record(
                .mainActorHeartbeat,
                attributes: [
                    "agentstudio.performance.mainactor.heartbeat_gap_ms": .double(
                        Double(heartbeat.gapNanoseconds) / 1_000_000),
                    "agentstudio.performance.mainactor.consecutive_overdue.count": .int(
                        Self.intClamped(overdueCount)),
                ]
            )
        case .contraction(let stage, let count):
            record(
                .pipelineContraction,
                attributes: [
                    Self.contractionCountAttributeKey(stage): .int(Self.intClamped(count))
                ]
            )
        case .runStage:
            break
        }
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

    private static func intClamped(_ value: UInt64) -> Int {
        value > UInt64(Int.max) ? Int.max : Int(value)
    }

    private static func contractionCountAttributeKey(_ stage: PerformanceContractionStage) -> String {
        switch stage {
        case .source:
            "agentstudio.performance.contraction.source.count"
        case .admitted:
            "agentstudio.performance.contraction.admitted.count"
        case .coalesced:
            "agentstudio.performance.contraction.coalesced.count"
        case .fact:
            "agentstudio.performance.contraction.fact.count"
        case .delivered:
            "agentstudio.performance.contraction.delivered.count"
        case .mainActorApply:
            "agentstudio.performance.contraction.mainactor_apply.count"
        case .rendered:
            "agentstudio.performance.contraction.rendered.count"
        }
    }
}
