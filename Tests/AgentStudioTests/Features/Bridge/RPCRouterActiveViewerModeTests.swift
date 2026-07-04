import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RPCRouterActiveViewerModeTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

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

    private actor SendableBox<Value> {
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func set(_ newValue: Value) {
            value = newValue
        }

        func get() -> Value {
            value
        }
    }

    @Test
    func test_pre_ready_active_viewer_mode_update_is_accepted_as_control_signal() async throws {
        // Arrange
        let router = RPCRouter()
        let receivedParams = SendableBox<BridgeActiveViewerModeUpdateMethod.Params?>(nil)
        var errorCode: Int?
        router.register(method: BridgeActiveViewerModeUpdateMethod.self) { params in
            await receivedParams.set(params)
            return nil
        }
        router.onError = { code, _, _ in errorCode = code }

        // Act
        let activeModeNotification = """
            {
              "jsonrpc": "2.0",
              "method": "bridge.activeViewerMode.update",
              "params": {
                "sessionId": "session-1",
                "sequence": 1,
                "mode": "file",
                "activeSource": {
                  "protocol": "worktree-file",
                  "streamId": "worktree-file:pane-1",
                  "generation": 3
                }
              }
            }
            """
        await router.dispatch(
            json: activeModeNotification,
            isBridgeReady: false
        )

        // Assert
        let params = try #require(await receivedParams.get())
        #expect(params.sessionId == "session-1")
        #expect(params.sequence == 1)
        #expect(params.mode == .file)
        #expect(params.activeSource?.protocolId == .worktreeFile)
        #expect(params.activeSource?.streamId == "worktree-file:pane-1")
        #expect(params.activeSource?.generation == 3)
        #expect(errorCode == nil)
    }

    @Test
    func test_page_world_active_viewer_mode_update_is_allowed() async throws {
        // Arrange
        let router = RPCRouter()
        let receivedParams = SendableBox<BridgeActiveViewerModeUpdateMethod.Params?>(nil)
        var errorCode: Int?
        router.register(method: BridgeActiveViewerModeUpdateMethod.self) { params in
            await receivedParams.set(params)
            return nil
        }
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: #"""
                {
                  "jsonrpc": "2.0",
                  "method": "bridge.activeViewerMode.update",
                  "__bridgeOrigin": "pageWorldLegacy",
                  "params": {
                    "sessionId": "session-1",
                    "sequence": 2,
                    "mode": "review",
                    "activeSource": null
                  }
                }
                """#,
            isBridgeReady: true
        )

        // Assert
        let params = try #require(await receivedParams.get())
        #expect(params.mode == .review)
        #expect(params.activeSource == nil)
        #expect(errorCode == nil)
    }

    @Test
    func stale_generation_active_viewer_mode_rejection_records_telemetry() async throws {
        // Arrange
        let recorder = BridgeTelemetryRecorderSpy()
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .fileViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
            ),
            metadata: PaneMetadata(
                contentType: .diff,
                title: "Files",
                facets: PaneContextFacets(repoId: UUIDv7.generate(), worktreeId: UUIDv7.generate())
            ),
            telemetryRecorder: recorder
        )
        defer { controller.teardown() }

        // Act
        await controller.handleIncomingRPC(
            #"""
            {
              "jsonrpc": "2.0",
              "method": "bridge.activeViewerMode.update",
              "params": {
                "sessionId": "session-stale-generation",
                "sequence": 1,
                "mode": "file",
                "activeSource": {
                  "protocol": "worktree-file",
                  "streamId": "worktree-file:pane-1",
                  "generation": 3
                }
              }
            }
            """#
        )

        // Assert
        let sample = try #require(
            await recorder.samples().first {
                $0.name == "performance.bridge.swift.active_viewer_mode_signal_rejected"
            }
        )
        #expect(
            sample.stringAttributes["agentstudio.bridge.active_viewer.signal_rejection_reason"]
                == "stale_generation"
        )
        #expect(sample.stringAttributes["agentstudio.bridge.active_viewer.mode"] == "file")
        #expect(sample.stringAttributes["agentstudio.bridge.active_source.protocol"] == "worktree-file")
    }

    @Test
    func stale_sequence_active_viewer_mode_rejection_records_telemetry() async throws {
        // Arrange
        let recorder = BridgeTelemetryRecorderSpy()
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .fileViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
            ),
            metadata: PaneMetadata(
                contentType: .diff,
                title: "Files",
                facets: PaneContextFacets(repoId: UUIDv7.generate(), worktreeId: UUIDv7.generate())
            ),
            telemetryRecorder: recorder
        )
        defer { controller.teardown() }

        // Act
        await controller.handleIncomingRPC(
            #"""
            {
              "jsonrpc": "2.0",
              "method": "bridge.activeViewerMode.update",
              "params": {
                "sessionId": "session-stale-sequence",
                "sequence": 2,
                "mode": "review",
                "activeSource": null
              }
            }
            """#
        )
        await controller.handleIncomingRPC(
            #"""
            {
              "jsonrpc": "2.0",
              "method": "bridge.activeViewerMode.update",
              "params": {
                "sessionId": "session-stale-sequence",
                "sequence": 1,
                "mode": "file",
                "activeSource": null
              }
            }
            """#
        )

        // Assert
        let sample = try #require(
            await recorder.samples().first {
                $0.name == "performance.bridge.swift.active_viewer_mode_signal_rejected"
                    && $0.stringAttributes["agentstudio.bridge.active_viewer.signal_rejection_reason"]
                        == "stale_sequence"
            }
        )
        #expect(sample.stringAttributes["agentstudio.bridge.active_viewer.mode"] == "file")
        #expect(sample.stringAttributes["agentstudio.bridge.active_source.protocol"] == "none")
    }
}
