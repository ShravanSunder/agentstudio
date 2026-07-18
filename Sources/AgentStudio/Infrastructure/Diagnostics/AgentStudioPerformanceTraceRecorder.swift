import Foundation

final class AgentStudioPerformanceTraceRecorder: @unchecked Sendable {
    enum Event: String, Sendable {
        case atomDerived = "performance.atom.derived"
        case atomMutation = "performance.atom.mutation"
        case atomRead = "performance.atom.read"
        case commandBarFilter = "performance.commandbar.filter"
        case commandBarItems = "performance.commandbar.items"
        case coordinatorWrite = "performance.coordinator.write"
        case filesystemLogicalDebt = "performance.filesystem.logical_debt"
        case gitAdmission = "performance.git.admission"
        case gitEventPosted = "performance.git.event_posted"
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
        case terminalForceGeometrySync = "performance.terminal.force_geometry_sync"
        case terminalGeometrySync = "performance.terminal.geometry_sync"
        case terminalMountLayout = "performance.terminal.mount_layout"
        case terminalSurfaceSizeDidChange = "performance.terminal.surface_size"
    }

    private let traceRuntime: AgentStudioTraceRuntime?
    private let eventQueue: AgentStudioTraceEventQueue?
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

}
