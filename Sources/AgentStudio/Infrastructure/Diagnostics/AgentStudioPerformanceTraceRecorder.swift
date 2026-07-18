import Foundation

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
        case gitAdmission = "performance.git.admission"
        case gitBackoff = "performance.git.backoff"
        case gitEventPosted = "performance.git.event_posted"
        case gitPathQuarantine = "performance.git.path_quarantine"
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
    private let lock = NSLock()
    private var topologyLookupAdmission = TopologyLookupTraceAdmission()

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
