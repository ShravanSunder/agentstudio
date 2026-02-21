import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct BridgePaneControllerTests {
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
}
