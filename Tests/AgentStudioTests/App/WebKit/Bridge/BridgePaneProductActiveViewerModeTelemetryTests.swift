import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    @MainActor
    @Suite("Bridge active-viewer accepted telemetry", .serialized)
    struct BridgePaneProductActiveViewerModeTelemetryTests {
        init() {
            installTestCoreAtomsIfNeeded()
        }

        @Test("accepted File mode emits once for one mode and source edge")
        func acceptedFileModeEmitsOnceForOneModeAndSourceEdge() async throws {
            let recorder = ActiveViewerModeTelemetryRecorder()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(
                        rootPath: "/tmp/product-file-viewer",
                        baseline: .unstaged
                    )
                ),
                appRootURL: testBridgeAppRootURL(),
                telemetryRecorder: recorder,
                initialPaneActivity: .foreground
            )
            defer { controller.teardown() }
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            let activeSource = BridgeActiveViewerSource(
                protocolId: .worktreeFile,
                streamId: "product-file-stream",
                generation: 41
            )

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-session",
                sequence: 1,
                mode: .file,
                activeSource: activeSource,
                productAdmission: productAdmission
            )
            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-session",
                sequence: 2,
                mode: .file,
                activeSource: activeSource,
                productAdmission: productAdmission
            )

            let samples = await recorder.samples().filter {
                $0.name == "performance.bridge.swift.active_viewer_mode_signal_accepted"
            }
            #expect(samples.count == 1)
            #expect(samples.first?.stringAttributes["agentstudio.bridge.active_viewer.mode"] == "file")
            #expect(samples.first?.numericAttributes["agentstudio.bridge.source.generation"] == 41)
        }
    }
}

private actor ActiveViewerModeTelemetryRecorder: BridgePerformanceTraceRecording {
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
        _ = (reason, droppedCount, firstRejectedEventName, receivedAtUnixNano)
    }

    func drain() async throws {}

    func samples() -> [BridgeTelemetrySample] {
        recordedSamples
    }
}
