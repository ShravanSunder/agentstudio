import Foundation

@MainActor
package final class AtomPerformanceTelemetry {
    package static let shared = AtomPerformanceTelemetry()

    private var traceRuntime: AgentStudioTraceRuntime?
    private var eventQueue: AgentStudioTraceEventQueue?
    private var repoExplorerKeyClass: String?
    private var repoExplorerFacet: String?
    private var repoExplorerRowRelation: String?
    private var repoExplorerStageSequence: [String: UInt64] = [:]

    private init() {}

    package func configure(traceRuntime: AgentStudioTraceRuntime?) {
        self.traceRuntime = traceRuntime
        if let traceRuntime,
            traceRuntime.isEnabled(.atoms) || traceRuntime.isEnabled(.performance)
        {
            self.eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            self.eventQueue = nil
        }
    }

    func resetForTests() {
        eventQueue?.cancel()
        traceRuntime = nil
        eventQueue = nil
        repoExplorerStageSequence = [:]
    }

    func drainForTests() async throws {
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    package func setRepoExplorerKeyedWakeContext(
        keyClass: String?,
        facet: String? = nil,
        rowRelation: String? = nil
    ) {
        repoExplorerKeyClass = keyClass
        repoExplorerFacet = facet
        repoExplorerRowRelation = rowRelation
    }

    package var isRepoExplorerKeyedWakeContextActive: Bool {
        repoExplorerKeyClass != nil
    }

    package func repoExplorerKeyedWakeSequence(for stage: String) -> UInt64 {
        repoExplorerStageSequence[stage, default: 0]
    }

    package func recordRepoExplorerKeyedWake(stage: String, outcome: String) {
        guard let traceRuntime, traceRuntime.isEnabled(.performance), let eventQueue,
            let repoExplorerKeyClass
        else { return }
        repoExplorerStageSequence[stage, default: 0] &+= 1
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.repo_explorer.stage": .string(stage),
            "agentstudio.performance.repo_explorer.key_class": .string(repoExplorerKeyClass),
            "agentstudio.performance.repo_explorer.outcome": .string(outcome),
        ]
        if let repoExplorerFacet {
            attributes["agentstudio.performance.repo_explorer.facet"] = .string(repoExplorerFacet)
        }
        if let repoExplorerRowRelation {
            attributes["agentstudio.performance.repo_explorer.row_relation"] = .string(repoExplorerRowRelation)
        }
        eventQueue.record(
            tag: .performance,
            body: AgentStudioPerformanceTraceRecorder.Event.repoExplorerKeyedWake.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }

    func recordRead(
        kind: String,
        label: String,
        operation: String,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil,
        cacheHit: Bool? = nil
    ) {
        record(
            .atomRead,
            kind: kind,
            label: label,
            operation: operation,
            slotCount: slotCount,
            cachedKeyCount: cachedKeyCount,
            cacheHit: cacheHit
        )
    }

    func recordMutation(
        kind: String,
        label: String,
        operation: String,
        acceptedChangeCount: Int,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil
    ) {
        record(
            .atomMutation,
            kind: kind,
            label: label,
            operation: operation,
            acceptedChangeCount: acceptedChangeCount,
            slotCount: slotCount,
            cachedKeyCount: cachedKeyCount
        )
    }

    func recordDerived(
        operation: String,
        inputRevisionCount: Int,
        cacheHit: Bool
    ) {
        record(
            .atomDerived,
            kind: "derived_value",
            label: nil,
            operation: operation,
            inputRevisionCount: inputRevisionCount,
            cacheHit: cacheHit
        )
    }

    func recordEagerDerivedFamily(
        label: String,
        operation: String,
        outcome: String? = nil
    ) {
        record(
            .atomDerived,
            kind: "eager_derived_family",
            label: label,
            operation: operation,
            outcome: outcome
        )
    }

    private func record(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        kind: String,
        label: String?,
        operation: String,
        acceptedChangeCount: Int? = nil,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil,
        inputRevisionCount: Int? = nil,
        cacheHit: Bool? = nil,
        outcome: String? = nil
    ) {
        guard let traceRuntime, traceRuntime.isEnabled(.atoms), let eventQueue else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.atom.kind": .string(kind),
            "agentstudio.performance.atom.operation": .string(operation),
        ]
        if let label {
            attributes["agentstudio.performance.atom.label"] = .string(label)
        }
        if let acceptedChangeCount {
            attributes["agentstudio.performance.atom.accepted_change.count"] = .int(acceptedChangeCount)
        }
        if let slotCount {
            attributes["agentstudio.performance.atom.slot.count"] = .int(slotCount)
        }
        if let cachedKeyCount {
            attributes["agentstudio.performance.atom.cached_key.count"] = .int(cachedKeyCount)
        }
        if let inputRevisionCount {
            attributes["agentstudio.performance.atom.input_revision.count"] = .int(inputRevisionCount)
        }
        if let cacheHit {
            attributes["agentstudio.performance.atom.cache_hit"] = .bool(cacheHit)
        }
        if let outcome {
            attributes["agentstudio.performance.atom.outcome"] = .string(outcome)
        }
        eventQueue.record(
            tag: .atoms,
            body: event.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }
}
