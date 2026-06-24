import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RPCRouterTelemetryTests {
    private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            receivedAtUnixNano: UInt64
        ) async {}

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drain() async throws {}
    }

    private actor BridgeTelemetryIngestorSpy: BridgeTelemetryBatchIngesting {
        private var ingestCount = 0

        func ingest(_ data: Data) async -> BridgeTelemetryIngestResult {
            ingestCount += 1
            return .accepted(sampleCount: 1)
        }

        func count() -> Int {
            ingestCount
        }
    }

    @Test
    func oversized_bridge_telemetry_rpc_records_drop_before_rejection() async {
        // Arrange
        let router = RPCRouter()
        let recorder = BridgeTelemetryRecorderSpy()
        let ingestor = BridgeTelemetryIngestorSpy()
        router.telemetryRecorder = recorder
        router.telemetryIngestor = ingestor
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }
        let oversizedBody = String(
            repeating: "a",
            count: BridgeTelemetryLimits.maxEncodedBatchBytes
        )

        // Act
        await router.dispatch(
            json:
                #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":{"schemaVersion":1,"scenario":"test","samples":[],"body":""#
                + oversizedBody
                + #""}}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
        #expect(await ingestor.count() == 0)
        let telemetryBatch = await recorder.samples().first
        #expect(telemetryBatch?.name == "performance.bridge.webkit.telemetry_batch")
        #expect(
            telemetryBatch?.stringAttributes["agentstudio.bridge.telemetry.drop_reason"]
                == BridgeTelemetryDropReason.encodedBatchTooLarge.rawValue
        )
        #expect(telemetryBatch?.stringAttributes["agentstudio.bridge.plane"] == "observability")
        #expect(telemetryBatch?.stringAttributes["agentstudio.bridge.priority"] == "best_effort")
        #expect(telemetryBatch?.stringAttributes["agentstudio.bridge.slice"] == "telemetry_batch")
    }
}
