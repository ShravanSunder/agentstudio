import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryIngestorTests {
    @Test
    func ingestorDecodesAndForwardsValidatedSamples() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: 3,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "package_apply"
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let data = try JSONEncoder().encode(batch)

        let result = await ingestor.ingest(data)

        #expect(result == .accepted(sampleCount: 1))
        #expect(await recorder.samples == batch.samples)
    }

    @Test
    func ingestorRecordsDropSummariesForRejectedBatches() async {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder
        )
        let data = Data(repeating: 65, count: BridgeTelemetryLimits.maxEncodedBatchBytes + 1)

        let result = await ingestor.ingest(data)

        #expect(result == .dropped(.encodedBatchTooLarge))
        #expect(await recorder.dropReasons == [.encodedBatchTooLarge])
    }

    @Test
    func ingestorRecordsSwiftIngestAccountingWhenSwiftScopeIsEnabled() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift, .web]),
            recorder: recorder
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: 3,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "package_apply"
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let data = try JSONEncoder().encode(batch)

        let result = await ingestor.ingest(data)
        let samples = await recorder.samples

        #expect(result == .accepted(sampleCount: 1))
        #expect(
            samples.map(\.name) == [
                "performance.bridge.web.package_apply",
                "performance.bridge.swift.telemetry_ingest",
            ])
        #expect(
            samples.last?.numericAttributes["agentstudio.bridge.batch.sample_count"] == 1
        )
    }
}

private actor RecordingBridgePerformanceTraceRecorder: BridgePerformanceTraceRecording {
    private(set) var samples: [BridgeTelemetrySample] = []
    private(set) var dropReasons: [BridgeTelemetryDropReason] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        samples.append(sample)
    }

    func recordDrop(reason: BridgeTelemetryDropReason, droppedCount: Int, receivedAtUnixNano: UInt64) async {
        dropReasons.append(reason)
    }
}
