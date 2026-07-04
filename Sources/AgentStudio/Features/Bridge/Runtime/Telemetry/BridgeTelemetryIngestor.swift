import Foundation

enum BridgeTelemetryIngestResult: Equatable, Sendable {
    case accepted(sampleCount: Int)
    case dropped(BridgeTelemetryDropReason)
}

actor BridgeTelemetryIngestor {
    private let scopeGate: BridgeTelemetryScopeGate
    private let recorder: any BridgePerformanceTraceRecording
    private let validator: BridgeTelemetryBatchValidator
    private let timeUnixNano: @Sendable () -> UInt64

    init(
        scopeGate: BridgeTelemetryScopeGate,
        recorder: any BridgePerformanceTraceRecording,
        timeUnixNano: @escaping @Sendable () -> UInt64 = BridgeTelemetryIngestor.currentTimeUnixNano
    ) {
        self.scopeGate = scopeGate
        self.recorder = recorder
        self.validator = BridgeTelemetryBatchValidator(scopeGate: scopeGate)
        self.timeUnixNano = timeUnixNano
    }

    func ingest(_ data: Data) async -> BridgeTelemetryIngestResult {
        let receivedAtUnixNano = timeUnixNano()
        let validationOutcome = validator.decodeAndValidateWithDetails(data)
        switch validationOutcome.result {
        case .accepted(let batch):
            for sample in batch.samples {
                await recorder.record(sample: sample, receivedAtUnixNano: receivedAtUnixNano)
            }
            await recordIngestTelemetry(
                phase: "accepted",
                sampleCount: batch.samples.count,
                receivedAtUnixNano: receivedAtUnixNano
            )
            return .accepted(sampleCount: batch.samples.count)
        case .dropped(let reason):
            await recorder.recordDrop(
                reason: reason,
                droppedCount: 1,
                firstRejectedEventName: validationOutcome.firstRejectedEventName,
                receivedAtUnixNano: receivedAtUnixNano
            )
            await recordIngestTelemetry(
                phase: "dropped",
                sampleCount: 0,
                receivedAtUnixNano: receivedAtUnixNano
            )
            return .dropped(reason)
        }
    }

    private func recordIngestTelemetry(
        phase: String,
        sampleCount: Int,
        receivedAtUnixNano: UInt64
    ) async {
        guard scopeGate.isEnabled(.swift) else {
            return
        }
        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.telemetry_ingest",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": phase,
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.observability.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.bestEffort.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.telemetryIngest.rawValue,
                    "agentstudio.bridge.transport": "swift",
                ],
                numericAttributes: ["agentstudio.bridge.batch.sample_count": Double(sampleCount)],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: receivedAtUnixNano
        )
    }

    private static func currentTimeUnixNano() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    }
}
