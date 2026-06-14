import Foundation

@MainActor
final class AtomPerformanceTelemetry {
    static let shared = AtomPerformanceTelemetry()

    private var traceRuntime: AgentStudioTraceRuntime?
    private var eventQueue: AgentStudioTraceEventQueue?

    private init() {}

    func configure(traceRuntime: AgentStudioTraceRuntime?) {
        self.traceRuntime = traceRuntime
        if let traceRuntime, traceRuntime.isEnabled(.atoms) {
            self.eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            self.eventQueue = nil
        }
    }

    func resetForTests() {
        eventQueue?.cancel()
        traceRuntime = nil
        eventQueue = nil
    }

    func drainForTests() async throws {
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    func recordRead(
        kind: String,
        operation: String,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil,
        cacheHit: Bool? = nil
    ) {
        record(
            .atomRead,
            kind: kind,
            operation: operation,
            slotCount: slotCount,
            cachedKeyCount: cachedKeyCount,
            cacheHit: cacheHit
        )
    }

    func recordMutation(
        kind: String,
        operation: String,
        acceptedChangeCount: Int,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil
    ) {
        record(
            .atomMutation,
            kind: kind,
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
            operation: operation,
            inputRevisionCount: inputRevisionCount,
            cacheHit: cacheHit
        )
    }

    private func record(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        kind: String,
        operation: String,
        acceptedChangeCount: Int? = nil,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil,
        inputRevisionCount: Int? = nil,
        cacheHit: Bool? = nil
    ) {
        guard let traceRuntime, traceRuntime.isEnabled(.atoms), let eventQueue else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.atom.kind": .string(kind),
            "agentstudio.performance.atom.operation": .string(operation),
        ]
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
        eventQueue.record(
            tag: .atoms,
            body: event.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }
}
