import Foundation
import Testing
import WebKit

@testable import AgentStudio

@Suite(.serialized)
struct BridgeSchemeHandlerTelemetryTests {
    private actor RecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            _ = receivedAtUnixNano
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            firstRejectedEventName: String?,
            receivedAtUnixNano: UInt64
        ) async {
            _ = reason
            _ = droppedCount
            _ = firstRejectedEventName
            _ = receivedAtUnixNano
        }

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drain() async throws {}
    }

    @Test
    func telemetryPostRouteAdmitsSingleDecodedBatch() async throws {
        let recorder = RecorderSpy()
        let handler = BridgeSchemeHandler(paneId: UUID(), telemetryRecorder: recorder)
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: BridgeTelemetryPlane.observability.rawValue,
                priority: BridgeTelemetryPriority.bestEffort.rawValue,
                slice: BridgeTelemetrySlice.telemetryDrop.rawValue,
                transport: "scheme",
                extraStrings: [
                    "agentstudio.bridge.telemetry.drop_reason": BridgeTelemetryDropReason.queueSaturated.rawValue,
                    "agentstudio.bridge.telemetry.event_name": "performance.bridge.web.rpc_send",
                    "agentstudio.bridge.telemetry.lane": "warm",
                    "agentstudio.bridge.telemetry.result": "success",
                ],
                extraNumbers: ["agentstudio.bridge.telemetry.dropped_count": 1]
            )
        )
        var request = URLRequest(url: try #require(URL(string: "agentstudio://telemetry/batch")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(batch)

        var events: [URLSchemeTaskResult] = []
        for try await result in handler.reply(for: request) {
            events.append(result)
        }

        #expect(events.count == 1)
        #expect(await recorder.samples().map(\.name) == ["performance.bridge.web.telemetry_drop"])
    }
}
