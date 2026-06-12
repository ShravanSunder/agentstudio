import Foundation

final class AgentStudioPerformanceTraceRecorder: @unchecked Sendable {
    enum Event: String, Sendable {
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
        case repoAndWorktreeLookup = "performance.topology.repo_and_worktree"
        case sidebarFilterInput = "performance.sidebar.filter_input"
        case sidebarProjection = "performance.sidebar.projection"
        case sidebarRowIndex = "performance.sidebar.row_index"
        case tabBarRefresh = "performance.tabbar.refresh"
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
}
