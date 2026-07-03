import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RPCRouterActiveViewerModeTests {
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
}
