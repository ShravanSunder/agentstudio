import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct BridgePaneControllerTests {
    private struct DiffRequestFileContentsMethod: RPCMethod {
        struct Params: Decodable {
            let fileId: String
        }

        typealias Result = RPCNoResponse
        static let method = "diff.requestFileContents"
    }

    @Test("handleBridgeReady sets bridge readiness and teardown resets it")
    func handleBridgeReady_setsReadyAndTeardownResets() {
        let controller = BridgePaneController(
            paneId: UUID(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )

        #expect(controller.isBridgeReady == false)

        controller.handleBridgeReady()
        #expect(controller.isBridgeReady == true)

        controller.teardown()
        #expect(controller.isBridgeReady == false)
    }

    @Test("handleBridgeReady is idempotent while ready")
    func handleBridgeReady_isIdempotent() {
        let controller = BridgePaneController(
            paneId: UUID(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )

        controller.handleBridgeReady()
        #expect(controller.isBridgeReady == true)

        controller.handleBridgeReady()
        #expect(controller.isBridgeReady == true)
    }

    @Test("teardown allows bridge ready cycle to restart")
    func teardown_allowsReadyToRestartAfterReset() {
        let controller = BridgePaneController(
            paneId: UUID(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )

        controller.handleBridgeReady()
        #expect(controller.isBridgeReady == true)

        controller.teardown()
        #expect(controller.isBridgeReady == false)

        controller.handleBridgeReady()
        #expect(controller.isBridgeReady == true)
    }

    @Test("non-ready command does not execute handler")
    func nonReady_command_does_not_execute_handler() async {
        // Arrange
        let controller = BridgePaneController(
            paneId: UUID(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )
        var executedFileId: String?

        controller.router.register(method: DiffRequestFileContentsMethod.self) { params in
            executedFileId = params.fileId
            return nil
        }

        // Act
        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{"fileId":"abc123"},"id":1}"#
        )

        // Assert
        #expect(controller.isBridgeReady == false)
        #expect(executedFileId == nil)
    }

    @Test("ready command executes handler")
    func ready_command_executes_handler() async {
        // Arrange
        let controller = BridgePaneController(
            paneId: UUID(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )
        var executedFileId: String?

        controller.router.register(method: DiffRequestFileContentsMethod.self) { params in
            executedFileId = params.fileId
            return nil
        }

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )
        #expect(controller.isBridgeReady == true)

        // Act
        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{"fileId":"abc123"},"id":1}"#
        )

        // Assert
        #expect(executedFileId == "abc123")
    }

    @Test("non-ready commands are dropped before bridge.ready")
    func nonReady_commands_are_dropped_before_bridge_ready() async {
        // Arrange
        let controller = BridgePaneController(
            paneId: UUID(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )
        var errorCode: Int?
        controller.router.onError = { code, _, _ in errorCode = code }

        // Act
        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{},"id":1}"#
        )

        // Assert
        #expect(controller.isBridgeReady == false)
        #expect(errorCode == nil)
    }
}
