import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerTelemetryTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("loadDiff records correlated Swift review telemetry")
        func loadDiff_records_correlated_swift_review_telemetry() async throws {
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: 100
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [changedFile]
                ),
                contentByHandleId: [:]
            )
            let recorder = BridgeTelemetryRecorderSpy()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider,
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift, .webKit]),
                telemetryRecorder: recorder,
                traceContextFactory: BridgeTraceContextFactory(
                    makeTraceId: { "11111111111111111111111111111111" },
                    makeSpanId: { "2222222222222222" }
                )
            )
            defer { controller.teardown() }
            let commandId = UUID()

            let result = await controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            let samples = await recorder.samples()
            let packageBuild = try #require(
                samples.first { $0.name == "performance.bridge.swift.package_build" }
            )
            let deltaBuild = try #require(
                samples.first { $0.name == "performance.bridge.swift.delta_build" }
            )
            let contentRegister = try #require(
                samples.first { $0.name == "performance.bridge.swift.content_register" }
            )
            #expect(packageBuild.traceContext?.traceId == "11111111111111111111111111111111")
            #expect(packageBuild.traceContext?.parentSpanId == nil)
            #expect(deltaBuild.traceContext?.parentSpanId == packageBuild.traceContext?.spanId)
            #expect(contentRegister.traceContext?.parentSpanId == packageBuild.traceContext?.spanId)
            #expect(packageBuild.stringAttributes["agentstudio.bridge.phase"] == "package_build")
            #expect(packageBuild.stringAttributes["agentstudio.bridge.plane"] == "data")
            #expect(packageBuild.stringAttributes["agentstudio.bridge.priority"] == "cold")
            #expect(packageBuild.stringAttributes["agentstudio.bridge.slice"] == "review_metadata")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.phase"] == "delta_build")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.plane"] == "data")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.priority"] == "warm")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.slice"] == "review_delta")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.phase"] == "content_register")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.plane"] == "data")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.priority"] == "cold")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.slice"] == "review_metadata")
        }

        @Test("release-style telemetry policy disables bridge telemetry wiring")
        func releaseStyleTelemetryPolicyDisablesBridgeTelemetryWiring() async {
            let recorder = BridgeTelemetryRecorderSpy()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
                ),
                telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy(isDebugBuild: false),
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit]),
                telemetryRecorder: recorder
            )
            defer { controller.teardown() }
            var errorCode: Int?
            controller.router.onError = { code, _, _ in errorCode = code }

            await controller.recordSwiftTelemetry(
                name: "performance.bridge.swift.package_build",
                phase: "package_build",
                priorityHint: .warm,
                traceContext: nil,
                durationMilliseconds: 1
            )
            await controller.router.dispatch(
                json:
                    #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":{"schemaVersion":1,"scenario":"package_apply_content_fetch_v1","samples":[]}}"#,
                isBridgeReady: true
            )

            #expect(controller.router.telemetryRecorder == nil)
            #expect(controller.router.telemetryIngestor == nil)
            #expect(errorCode == -32_601)
            #expect(await recorder.samples().isEmpty)
        }

        @Test("IPC telemetry flush failure does not return a flushed success result")
        func ipcTelemetryFlushFailure_doesNotReturnFlushedSuccessResult() async {
            let recorder = BridgeTelemetryRecorderSpy()
            await recorder.setDrainFailure()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                telemetryRecorder: recorder
            )
            defer { controller.teardown() }

            await #expect(throws: BridgeTelemetryRecorderSpy.Failure.self) {
                _ = try await controller.flushTelemetryForIPC()
            }
        }
    }
}

private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
    enum Failure: Error {
        case drainFailed
    }

    private var recordedSamples: [BridgeTelemetrySample] = []
    private var recordedDrops: [BridgeTelemetryDropReason] = []
    private var shouldFailDrain = false

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        recordedSamples.append(sample)
    }

    func recordDrop(
        reason: BridgeTelemetryDropReason,
        droppedCount: Int,
        receivedAtUnixNano: UInt64
    ) async {
        recordedDrops.append(reason)
    }

    func samples() -> [BridgeTelemetrySample] {
        recordedSamples
    }

    func setDrainFailure() {
        shouldFailDrain = true
    }

    func drain() async throws {
        if shouldFailDrain {
            throw Failure.drainFailed
        }
    }
}
