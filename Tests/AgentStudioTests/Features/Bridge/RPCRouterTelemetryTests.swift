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
    func productionSystemBridgeTelemetryRouteIsCompileDead() async throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let systemMethods = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/Methods/SystemMethods.swift"),
            encoding: .utf8
        )
        let dispatcherSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeCommandDispatcher.swift"),
            encoding: .utf8
        )

        #expect(!systemMethods.contains("BridgeTelemetryMethod"))
        #expect(!dispatcherSource.contains("dispatchBridgeTelemetryBatch"))
    }

    @Test
    func interactiveRPCRejectsLegacyTelemetryMethodWithoutSelfObservation() async {
        // Arrange
        let router = BridgeSchemeCommandDispatcher()
        let recorder = BridgeTelemetryRecorderSpy()
        router.telemetryRecorder = recorder
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json:
                #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":{"schemaVersion":1,"scenario":"test","samples":[]}}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_601)
        #expect(await recorder.samples().isEmpty)
    }

}
