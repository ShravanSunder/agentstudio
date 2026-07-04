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
                    name: "performance.bridge.web.push_apply",
                    durationMilliseconds: 3,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "apply",
                        "agentstudio.bridge.plane": "data",
                        "agentstudio.bridge.priority": "cold",
                        "agentstudio.bridge.slice": "review_metadata",
                        "agentstudio.bridge.transport": "intake",
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
    func ingestorRecordsAllowedFirstRejectedEventNameForUnsafeRejectedBatches() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder
        )
        let rejectedSampleName = "performance.bridge.web.selected_content_painted"
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: rejectedSampleName,
                    durationMilliseconds: 3,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "selected_content_painted",
                        "agentstudio.bridge.plane": "data",
                        "agentstudio.bridge.priority": "hot",
                        "agentstudio.bridge.slice": "code_view_item",
                        "agentstudio.bridge.transport": "swift",
                        "agentstudio.bridge.viewer": "review",
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        let result = await ingestor.ingest(try JSONEncoder().encode(batch))

        #expect(result == .dropped(.unsafeAttribute))
        #expect(await recorder.dropReasons == [.unsafeAttribute])
        #expect(await recorder.firstRejectedEventNames == [rejectedSampleName])
    }

    @Test
    func ingestorRedactsUnknownFirstRejectedEventNameForUnrecognizedRejectedSamples() async throws {
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
                    name: "performance.bridge.web.cmd_private_payload",
                    durationMilliseconds: 3,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        let result = await ingestor.ingest(try JSONEncoder().encode(batch))

        #expect(result == .dropped(.unsafeEventName))
        #expect(await recorder.dropReasons == [.unsafeEventName])
        #expect(await recorder.firstRejectedEventNames == ["unknown"])
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
                    name: "performance.bridge.web.push_apply",
                    durationMilliseconds: 3,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "apply",
                        "agentstudio.bridge.plane": "data",
                        "agentstudio.bridge.priority": "cold",
                        "agentstudio.bridge.slice": "review_metadata",
                        "agentstudio.bridge.transport": "intake",
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
                "performance.bridge.web.push_apply",
                "performance.bridge.swift.telemetry_ingest",
            ])
        #expect(
            samples.last?.numericAttributes["agentstudio.bridge.batch.sample_count"] == 1
        )
        #expect(samples.last?.stringAttributes["agentstudio.bridge.phase"] == "accepted")
        #expect(samples.last?.stringAttributes["agentstudio.bridge.plane"] == "observability")
        #expect(samples.last?.stringAttributes["agentstudio.bridge.priority"] == "best_effort")
        #expect(samples.last?.stringAttributes["agentstudio.bridge.slice"] == "telemetry_ingest")
        #expect(samples.last?.stringAttributes["agentstudio.bridge.transport"] == "swift")
    }
}

private actor RecordingBridgePerformanceTraceRecorder: BridgePerformanceTraceRecording {
    private(set) var samples: [BridgeTelemetrySample] = []
    private(set) var dropReasons: [BridgeTelemetryDropReason] = []
    private(set) var firstRejectedEventNames: [String?] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        samples.append(sample)
    }

    func recordDrop(
        reason: BridgeTelemetryDropReason,
        droppedCount: Int,
        firstRejectedEventName: String?,
        receivedAtUnixNano: UInt64
    ) async {
        dropReasons.append(reason)
        firstRejectedEventNames.append(firstRejectedEventName)
    }

    func drain() async throws {}
}
