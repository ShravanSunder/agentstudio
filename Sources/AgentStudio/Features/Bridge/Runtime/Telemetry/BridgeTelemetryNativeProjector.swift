import Foundation

enum BridgeTelemetryNativeProjectorError: Error, Equatable {
    case invalidSample
}

struct BridgeTelemetryNativeProjector: Sendable {
    private let recorder: any BridgePerformanceTraceRecording
    private let eventValidator: BridgeTelemetryEventValidator

    init(recorder: any BridgePerformanceTraceRecording) {
        self.recorder = recorder
        self.eventValidator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
    }

    func project(_ request: BridgeTelemetryBatchRequest) async throws -> BridgeTelemetryNativeProjectionResult {
        for stampedSample in request.samples {
            let projection = try projectedSample(stampedSample.sample)
            await recorder.record(
                sample: projection.sample,
                receivedAtUnixNano: projection.eventTimeUnixNano
            )
        }
        let acceptedLossCount = request.lossSummaries.reduce(into: 0) { count, summary in
            count += summary.requiredCount + summary.optionalCount
        }
        return BridgeTelemetryNativeProjectionResult(
            acceptedSampleCount: request.samples.count,
            acceptedLossCount: acceptedLossCount,
            nativeRequiredLossCount: 0,
            nativeOptionalLossCount: 0
        )
    }

    private func projectedSample(
        _ compactSample: BridgeTelemetryCompactSample
    ) throws -> (sample: BridgeTelemetrySample, eventTimeUnixNano: UInt64) {
        switch compactSample {
        case .lifecycle(let value):
            return (
                correlatedSample(
                    name: "performance.bridge.web.interaction_lifecycle",
                    phase: value.stage.rawValue,
                    attemptId: value.attemptId,
                    interactionSequence: value.interactionSequence,
                    surface: value.surface,
                    durationMilliseconds: nil
                ),
                eventTimeUnixNano(value.timestampMilliseconds)
            )
        case .duration(let value):
            return (
                correlatedSample(
                    name: "performance.bridge.web.interaction_duration",
                    phase: value.metric.rawValue,
                    attemptId: value.attemptId,
                    interactionSequence: value.interactionSequence,
                    surface: value.surface,
                    durationMilliseconds: value.durationMilliseconds
                ),
                eventTimeUnixNano(value.timestampMilliseconds)
            )
        case .failure(let value):
            return (
                correlatedSample(
                    name: "performance.bridge.web.interaction_failure",
                    phase: value.failure.rawValue,
                    attemptId: value.attemptId,
                    interactionSequence: value.interactionSequence,
                    surface: value.surface,
                    durationMilliseconds: nil
                ),
                eventTimeUnixNano(value.timestampMilliseconds)
            )
        case .integrity(let value):
            return (
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.telemetry_integrity",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: baseAttributes(
                        phase: value.failure.rawValue,
                        priority: .hot
                    ),
                    numericAttributes: [:],
                    booleanAttributes: [:]
                ),
                eventTimeUnixNano(value.timestampMilliseconds)
            )
        case .diagnostic(let value):
            return (
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.telemetry_diagnostic",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: baseAttributes(
                        phase: value.code.rawValue,
                        priority: .bestEffort
                    ),
                    numericAttributes: ["agentstudio.bridge.telemetry.value": value.value],
                    booleanAttributes: [:]
                ),
                eventTimeUnixNano(value.timestampMilliseconds)
            )
        case .requiredEvent(let value), .optionalEvent(let value):
            guard case .accepted = eventValidator.validate(value.sample) else {
                throw BridgeTelemetryNativeProjectorError.invalidSample
            }
            return (value.sample, eventTimeUnixNano(value.timestampMilliseconds))
        }
    }

    private func correlatedSample(
        name: String,
        phase: String,
        attemptId: String,
        interactionSequence: Int,
        surface: BridgeTelemetrySurface,
        durationMilliseconds: Double?
    ) -> BridgeTelemetrySample {
        var stringAttributes = baseAttributes(phase: phase, priority: .hot)
        stringAttributes["agentstudio.bridge.interaction.attempt_id"] = attemptId
        stringAttributes["agentstudio.bridge.surface"] = surface.rawValue
        return BridgeTelemetrySample(
            scope: .web,
            name: name,
            durationMilliseconds: durationMilliseconds,
            traceContext: nil,
            stringAttributes: stringAttributes,
            numericAttributes: [
                "agentstudio.bridge.interaction.sequence": Double(interactionSequence)
            ],
            booleanAttributes: [:]
        )
    }

    private func baseAttributes(
        phase: String,
        priority: BridgeTelemetryPriority
    ) -> [String: String] {
        [
            "agentstudio.bridge.phase": phase,
            "agentstudio.bridge.plane": BridgeTelemetryPlane.observability.rawValue,
            "agentstudio.bridge.priority": priority.rawValue,
            "agentstudio.bridge.slice": "telemetry_sidecar",
            "agentstudio.bridge.transport": "scheme",
        ]
    }

    private func eventTimeUnixNano(_ timestampMilliseconds: Double) -> UInt64 {
        let nanoseconds = timestampMilliseconds * 1_000_000
        guard nanoseconds.isFinite, nanoseconds >= 0, nanoseconds <= Double(UInt64.max) else {
            return 0
        }
        return UInt64(nanoseconds)
    }
}
