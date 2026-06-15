import Foundation

protocol BridgePerformanceTraceRecording: Sendable {
    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async
    func recordDrop(reason: BridgeTelemetryDropReason, droppedCount: Int, receivedAtUnixNano: UInt64) async
}

struct BridgePerformanceTraceRecord: Sendable {
    let sample: BridgeTelemetrySample
    let eventTimeUnixNano: UInt64?
}

final class BridgePerformanceTraceRecorder: @unchecked Sendable, BridgePerformanceTraceRecording {
    private let traceRuntime: AgentStudioTraceRuntime?
    private let scopeGate: BridgeTelemetryScopeGate
    private let eventQueue: AgentStudioTraceEventQueue?
    private let scenario: String

    init(
        traceRuntime: AgentStudioTraceRuntime?,
        scenario: String = BridgeTelemetryBootstrapConfig.packageApplyContentFetchScenario
    ) {
        self.traceRuntime = traceRuntime
        self.scopeGate = BridgeTelemetryScopeGate(traceRuntime: traceRuntime)
        self.scenario = scenario
        if let traceRuntime, scopeGate.isEnabled {
            self.eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            self.eventQueue = nil
        }
    }

    var isEnabled: Bool {
        eventQueue != nil
    }

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        await emit(BridgePerformanceTraceRecord(sample: sample, eventTimeUnixNano: receivedAtUnixNano))
    }

    func recordDrop(reason: BridgeTelemetryDropReason, droppedCount: Int, receivedAtUnixNano: UInt64) async {
        await record(
            sample: BridgeTelemetrySample(
                scope: .web,
                name: "performance.bridge.web.telemetry_drop",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "dropped",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.observability.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.bestEffort.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.telemetryDrop.rawValue,
                    "agentstudio.bridge.telemetry.drop_reason": reason.rawValue,
                    "agentstudio.bridge.transport": "rpc",
                ],
                numericAttributes: [
                    "agentstudio.bridge.telemetry.dropped_count": Double(droppedCount)
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: receivedAtUnixNano
        )
    }

    func drain() async throws {
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    private func emit(_ record: BridgePerformanceTraceRecord) async {
        let sample = record.sample
        guard scopeGate.isEnabled(sample.scope), let eventQueue else { return }

        var attributes: [String: AgentStudioTraceValue] = [:]
        attributes.reserveCapacity(
            sample.stringAttributes.count + sample.numericAttributes.count + sample.booleanAttributes.count + 1
        )
        for (key, value) in sample.stringAttributes {
            attributes[key] = .string(value)
        }
        for (key, value) in sample.numericAttributes {
            attributes[key] = .double(value)
        }
        for (key, value) in sample.booleanAttributes {
            attributes[key] = .bool(value)
        }
        attributes["agentstudio.bridge.test.scenario"] = .string(scenario)
        if let durationMilliseconds = sample.durationMilliseconds {
            attributes["agentstudio.performance.elapsed_ms"] = .double(durationMilliseconds)
        }

        eventQueue.record(
            tag: sample.scope.traceTag,
            body: sample.name,
            traceID: sample.traceContext?.traceId,
            spanID: sample.traceContext?.spanId,
            parentSpanID: sample.traceContext?.parentSpanId,
            eventTimeUnixNano: record.eventTimeUnixNano,
            attributes: attributes
        )
    }
}
