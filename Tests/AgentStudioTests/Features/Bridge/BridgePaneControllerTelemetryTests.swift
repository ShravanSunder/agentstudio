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
            #expect(packageBuild.stringAttributes["agentstudio.bridge.slice"] == "diff_package_metadata")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.phase"] == "delta_build")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.plane"] == "data")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.priority"] == "warm")
            #expect(deltaBuild.stringAttributes["agentstudio.bridge.slice"] == "diff_package_delta")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.phase"] == "content_register")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.plane"] == "data")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.priority"] == "cold")
            #expect(contentRegister.stringAttributes["agentstudio.bridge.slice"] == "diff_package_metadata")
        }

        @Test("filesystem refresh records bounded invalidation and commit telemetry")
        func filesystemRefreshRecordsBoundedInvalidationAndCommitTelemetry() async throws {
            let recorder = BridgeTelemetryRecorderSpy()
            let fixture = makeRefreshRevisionFixture(telemetryRecorder: recorder)
            defer { fixture.controller.teardown() }
            let loadResult = await fixture.controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: UUIDv7.generate(),
                        worktreeId: fixture.headEndpoint.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: fixture.commandId,
                correlationId: nil
            )
            await setRefreshComparison(fixture, changedFile: fixture.refreshedFile)

            await postRefreshEvent(fixture, path: "Sources/App/New.swift", batchSeq: 1)

            #expect(loadResult == .success(commandId: fixture.commandId))
            let refreshSamples = await recorder.samples().filter { $0.name == "performance.bridge.refresh" }
            #expect(refreshSamples.count == 2)
            let invalidation = try #require(
                refreshSamples.first { $0.stringAttributes["agentstudio.bridge.phase"] == "invalidation" }
            )
            let finalCommit = try #require(
                refreshSamples.first { $0.stringAttributes["agentstudio.bridge.phase"] == "final_commit" }
            )
            #expect(invalidation.numericAttributes["agentstudio.performance.bridge.invalidation.count"] == 1)
            #expect(invalidation.numericAttributes["agentstudio.performance.bridge.coalesced_demand.count"] == 0)
            #expect(finalCommit.numericAttributes["agentstudio.performance.bridge.active_refresh.count"] == 1)
            #expect(finalCommit.numericAttributes["agentstudio.performance.bridge.final_commit.count"] == 1)
            #expect(finalCommit.durationMilliseconds != nil)
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
    }
}

actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
    private var recordedSamples: [BridgeTelemetrySample] = []
    private var recordedDrops: [BridgeTelemetryDropReason] = []

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
}
