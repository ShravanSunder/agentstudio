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
    func ingestorAttributesSequenceGapsToFirstBatchSampleWhenDropCounterIsMissing() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder
        )
        let firstResult = await ingestor.ingest(
            try JSONEncoder().encode(Self.selectedContentPaintedBatch(sequence: 1, sampleCount: 1))
        )
        let rejectedResult = await ingestor.ingest(
            try JSONEncoder().encode(Self.selectedContentPaintedBatch(sequence: 3, sampleCount: 1))
        )

        #expect(firstResult == .accepted(sampleCount: 1))
        #expect(rejectedResult == .dropped(.missingDropCounter))
        #expect(await recorder.firstRejectedEventNames == ["performance.bridge.web.selected_content_painted"])
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

    @Test
    func ingestorRateLimitsHighVolumeWebSamplesWithInjectedClock() async throws {
        let expectedAdmittedHighVolumeSampleCount = AppPolicies.Bridge.telemetryHighVolumeAdmissionLimit
        let clock = LockedUnixNanoClock(0)
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder,
            timeUnixNano: clock.now
        )

        for _ in 0..<4 {
            let result = await ingestor.ingest(
                try JSONEncoder().encode(Self.visibleDemandSettledBatch(sampleCount: 8))
            )
            #expect(result == .accepted(sampleCount: 8))
        }
        let saturatedResult = await ingestor.ingest(
            try JSONEncoder().encode(Self.visibleDemandSettledBatch(sampleCount: 2))
        )
        let saturatedSamples = await recorder.samples

        #expect(saturatedResult == .accepted(sampleCount: 0))
        #expect(saturatedSamples.count == expectedAdmittedHighVolumeSampleCount)
        #expect(await recorder.dropReasons == [.rateLimited])
        #expect(await recorder.droppedCounts == [2])
        #expect(await recorder.firstRejectedEventNames == ["performance.bridge.web.visible_demand_settled"])

        let stillSaturatedResult = await ingestor.ingest(
            try JSONEncoder().encode(
                BridgeTelemetryBatch(
                    schemaVersion: 1,
                    scenario: "package_apply_content_fetch_v1",
                    samples: [Self.visibleDemandSettledSample()]
                )
            )
        )

        #expect(stillSaturatedResult == .accepted(sampleCount: 0))
        #expect(await recorder.samples.count == expectedAdmittedHighVolumeSampleCount)
        #expect(await recorder.dropReasons == [.rateLimited, .rateLimited])

        clock.set(1_000_000_000)
        let refilledResult = await ingestor.ingest(
            try JSONEncoder().encode(
                BridgeTelemetryBatch(
                    schemaVersion: 1,
                    scenario: "package_apply_content_fetch_v1",
                    samples: [Self.visibleDemandSettledSample()]
                )
            )
        )

        #expect(refilledResult == .accepted(sampleCount: 1))
        #expect(await recorder.samples.count == expectedAdmittedHighVolumeSampleCount + 1)
    }

    @Test
    func ingestorKeepsLowVolumeWebSamplesUntouchedWhenHighVolumeBudgetIsSpent() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder,
            timeUnixNano: { 0 }
        )
        for _ in 0..<4 {
            let result = await ingestor.ingest(
                try JSONEncoder().encode(Self.visibleDemandSettledBatch(sampleCount: 8))
            )
            #expect(result == .accepted(sampleCount: 8))
        }
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: (0..<2).map { _ in
                Self.visibleDemandSettledSample()
            } + [Self.pushApplySample()]
        )

        let result = await ingestor.ingest(try JSONEncoder().encode(batch))
        let recordedNames = await recorder.samples.map(\.name)

        #expect(result == .accepted(sampleCount: 1))
        #expect(
            recordedNames.filter { $0 == "performance.bridge.web.visible_demand_settled" }.count
                == AppPolicies.Bridge.telemetryHighVolumeAdmissionLimit
        )
        #expect(recordedNames.last == "performance.bridge.web.push_apply")
        #expect(await recorder.dropReasons == [.rateLimited])
    }

    @Test
    func ingestorDoesNotRateLimitSelectedProofRowsWhenHighVolumeBudgetIsSpent() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder,
            timeUnixNano: { 0 }
        )
        for _ in 0..<4 {
            let result = await ingestor.ingest(
                try JSONEncoder().encode(Self.visibleDemandSettledBatch(sampleCount: 8))
            )
            #expect(result == .accepted(sampleCount: 8))
        }
        let proofBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                Self.selectedCodeViewItemMaterializeSample(),
                Self.selectedContentPaintedSample(),
            ]
        )

        let result = await ingestor.ingest(try JSONEncoder().encode(proofBatch))
        let recordedNames = await recorder.samples.map(\.name)

        #expect(result == .accepted(sampleCount: 2))
        #expect(recordedNames.suffix(2) == proofBatch.samples.map(\.name)[...])
        #expect(await recorder.dropReasons.isEmpty)
    }

    @Test
    func ingestorStillRateLimitsUnselectedMaterializeRowsWhenHighVolumeBudgetIsSpent() async throws {
        let recorder = RecordingBridgePerformanceTraceRecorder()
        let ingestor = BridgeTelemetryIngestor(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
            recorder: recorder,
            timeUnixNano: { 0 }
        )
        for _ in 0..<4 {
            let result = await ingestor.ingest(
                try JSONEncoder().encode(Self.visibleDemandSettledBatch(sampleCount: 8))
            )
            #expect(result == .accepted(sampleCount: 8))
        }
        let proofBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                Self.unselectedCodeViewItemMaterializeSample(),
                Self.selectedCodeViewItemMaterializeSample(),
            ]
        )

        let result = await ingestor.ingest(try JSONEncoder().encode(proofBatch))
        let recordedNames = await recorder.samples.map(\.name)
        let recordedMaterializeSample = await recorder.samples.last

        #expect(result == .accepted(sampleCount: 1))
        #expect(recordedNames.last == "performance.bridge.web.code_view_item_materialize")
        #expect(recordedMaterializeSample?.booleanAttributes["agentstudio.bridge.selected"] == true)
        #expect(await recorder.dropReasons == [.rateLimited])
        #expect(await recorder.droppedCounts == [1])
        #expect(await recorder.firstRejectedEventNames == ["performance.bridge.web.code_view_item_materialize"])
    }

    private static func selectedContentPaintedBatch(
        sequence: Int? = nil,
        sampleCount: Int
    ) -> BridgeTelemetryBatch {
        BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            sequence: sequence,
            samples: (0..<sampleCount).map { _ in Self.selectedContentPaintedSample() }
        )
    }

    private static func visibleDemandSettledBatch(sampleCount: Int) -> BridgeTelemetryBatch {
        BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: (0..<sampleCount).map { _ in Self.visibleDemandSettledSample() }
        )
    }

    private static func selectedCodeViewItemMaterializeSample() -> BridgeTelemetrySample {
        BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.code_view_item_materialize",
            durationMilliseconds: 3,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.content_bytes_bucket": "small",
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.language_class": "swift",
                "agentstudio.bridge.phase": "code_view_item_materialize",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.slice": "code_view_item",
                "agentstudio.bridge.transport": "swift",
                "agentstudio.bridge.viewer": "review",
            ],
            numericAttributes: [:],
            booleanAttributes: [
                "agentstudio.bridge.selected": true
            ]
        )
    }

    private static func unselectedCodeViewItemMaterializeSample() -> BridgeTelemetrySample {
        BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.code_view_item_materialize",
            durationMilliseconds: 3,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.content_bytes_bucket": "small",
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.language_class": "swift",
                "agentstudio.bridge.phase": "code_view_item_materialize",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.slice": "code_view_item",
                "agentstudio.bridge.transport": "swift",
                "agentstudio.bridge.viewer": "review",
            ],
            numericAttributes: [:],
            booleanAttributes: [
                "agentstudio.bridge.selected": false
            ]
        )
    }

    private static func selectedContentPaintedSample() -> BridgeTelemetrySample {
        BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.selected_content_painted",
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
            numericAttributes: [
                "agentstudio.bridge.selected_content.click_to_paint_ms": 7,
                "agentstudio.bridge.selected_content.frame_wait_ms": 2,
                "agentstudio.bridge.selected_content.materialize_ms": 5,
            ],
            booleanAttributes: [:]
        )
    }

    private static func visibleDemandSettledSample() -> BridgeTelemetrySample {
        BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.visible_demand_settled",
            durationMilliseconds: 3,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.content.role": "file",
                "agentstudio.bridge.demand.lane": "visible",
                "agentstudio.bridge.phase": "visible_demand_settled",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": "none",
                "agentstudio.bridge.slice": "content_fetch",
                "agentstudio.bridge.transport": "content",
                "agentstudio.bridge.viewer": "file",
            ],
            numericAttributes: [
                "agentstudio.bridge.content.first_chunk_wait_ms": 2,
                "agentstudio.bridge.content.response_wait_ms": 3,
                "agentstudio.bridge.content.stream_read_ms": 4,
                "agentstudio.bridge.demand.enqueue_accepted.count": 12,
                "agentstudio.bridge.demand.enqueue_rejected.count": 0,
                "agentstudio.bridge.demand.executor_in_flight_ms": 5,
                "agentstudio.bridge.demand.executor_pending_wait_ms": 6,
                "agentstudio.bridge.demand.failed.count": 0,
                "agentstudio.bridge.demand.intent.count": 12,
                "agentstudio.bridge.demand.loaded.count": 12,
                "agentstudio.bridge.demand.request.sequence": 8,
                "agentstudio.bridge.demand.scheduler_queue_wait_ms": 7,
                "agentstudio.bridge.visible_item.count": 12,
            ],
            booleanAttributes: [:]
        )
    }

    private static func pushApplySample() -> BridgeTelemetrySample {
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
    }
}

private actor RecordingBridgePerformanceTraceRecorder: BridgePerformanceTraceRecording {
    private(set) var samples: [BridgeTelemetrySample] = []
    private(set) var dropReasons: [BridgeTelemetryDropReason] = []
    private(set) var droppedCounts: [Int] = []
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
        droppedCounts.append(droppedCount)
        firstRejectedEventNames.append(firstRejectedEventName)
    }

    func drain() async throws {}
}

private final class LockedUnixNanoClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: UInt64) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}
