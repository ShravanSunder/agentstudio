import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct BridgePaneControllerSchemeRPCTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @MainActor
    @Test
    func reviewIntakeReadyWithStaleStreamReturnsErrorEnvelope() async throws {
        let paneId = UUIDv7.generate()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)
        controller.handleBridgeReady()

        let responseJSON = try #require(
            await controller.dispatchIncomingSchemeCommand(
                #"""
                {
                  "jsonrpc": "2.0",
                  "id": "intake-ready-stale",
                  "method": "bridge.intakeReady",
                  "params": {
                    "protocolId": "review",
                    "streamId": "review:stale-pane"
                  }
                }
                """#
            )
        )
        let envelope = try parseJSONObject(responseJSON)
        let error = try #require(envelope["error"] as? [String: Any])

        #expect(envelope["id"] as? String == "intake-ready-stale")
        #expect((error["code"] as? NSNumber)?.intValue == -32_602)
        #expect(error["message"] as? String == "review.intake_ready.stale_stream")

        await teardownBridgeControllerForTest(controller)
    }

    @MainActor
    @Test
    func bridgeReadyIsRejectedAsBootstrapOnly() async throws {
        let paneId = UUIDv7.generate()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)

        let responseJSON = try #require(
            await controller.dispatchIncomingSchemeCommand(
                #"""
                {
                  "jsonrpc": "2.0",
                  "id": "ready-over-scheme",
                  "method": "bridge.ready",
                  "params": {}
                }
                """#
            )
        )
        let envelope = try parseJSONObject(responseJSON)
        let error = try #require(envelope["error"] as? [String: Any])

        #expect(!(controller.isBridgeReady))
        #expect(envelope["id"] as? String == "ready-over-scheme")
        #expect((error["code"] as? NSNumber)?.intValue == -32_601)
        #expect(error["message"] as? String == "bridge.ready is bootstrap-only")

        await teardownBridgeControllerForTest(controller)
    }

    @MainActor
    @Test(arguments: [
        (#"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#, -32_600, "Invalid request"),
        (
            #"{"jsonrpc":"2.0","id":true,"method":"bridge.ready","params":{}}"#, -32_600,
            "Invalid request: invalid id"
        ),
    ])
    func malformedBridgeReadyFallsThroughToRouterValidation(
        requestJSON: String,
        expectedCode: Int,
        expectedMessage: String
    ) async throws {
        let paneId = UUIDv7.generate()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)

        let responseJSON = try #require(await controller.dispatchIncomingSchemeCommand(requestJSON))
        let envelope = try parseJSONObject(responseJSON)
        let error = try #require(envelope["error"] as? [String: Any])

        #expect((error["code"] as? NSNumber)?.intValue == expectedCode)
        #expect(error["message"] as? String == expectedMessage)

        await teardownBridgeControllerForTest(controller)
    }
}

@MainActor
private func teardownBridgeControllerForTest(_ controller: BridgePaneController) async {
    controller.teardown()
    await WebPageTestHarness.settle()
}

private func parseJSONObject(_ json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
