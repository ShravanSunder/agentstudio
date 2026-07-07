import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeReadyMessageHandlerTests {
    @Test
    func acceptsReadyBootstrapRequestOnly() {
        let json = #"{"jsonrpc":"2.0","id":"ready-1","method":"bridge.ready","params":{}}"#

        let result = BridgeReadyMessageHandler.extractReadyRequestId(from: json)

        #expect(result == "ready-1")
    }

    @Test
    func rejectsOrdinaryCommandJSON() {
        let json = #"{"jsonrpc":"2.0","id":"cmd-1","method":"bridge.intakeReady","params":{"protocolId":"review"}}"#

        let result = BridgeReadyMessageHandler.extractReadyRequestId(from: json)

        #expect(result == nil)
    }

    @Test
    func rejectsInvalidAndNonStringBodies() {
        #expect(BridgeReadyMessageHandler.extractReadyRequestId(from: "not json {{{") == nil)
        #expect(BridgeReadyMessageHandler.extractReadyRequestId(from: "") == nil)
        #expect(BridgeReadyMessageHandler.extractReadyRequestId(from: ["method": "bridge.ready"]) == nil)
        #expect(BridgeReadyMessageHandler.extractReadyRequestId(from: true) == nil)
        #expect(
            BridgeReadyMessageHandler.extractReadyRequestId(from: #"{"jsonrpc":"2.0","method":"bridge.ready"}"#) == nil)
    }

    @Test
    func decodesMalformedReadyBootstrapAsInvalidRequest() {
        #expect(
            BridgeReadyMessageHandler.decodeReadyBootstrapMessage(
                from: #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#)
                == .invalid(id: nil, message: "Invalid request"))
        #expect(
            BridgeReadyMessageHandler.decodeReadyBootstrapMessage(
                from: #"{"jsonrpc":"2.0","id":true,"method":"bridge.ready","params":{}}"#)
                == .invalid(id: nil, message: "Invalid request: invalid id"))
    }

    @Test
    func rejectsReadyBootstrapWithExtraFieldsOrParams() {
        #expect(
            BridgeReadyMessageHandler.decodeReadyBootstrapMessage(
                from: #"{"jsonrpc":"2.0","id":"ready-1","method":"bridge.ready","params":{"unexpected":true}}"#)
                == .invalid(id: "ready-1", message: "Invalid request"))
        #expect(
            BridgeReadyMessageHandler.decodeReadyBootstrapMessage(
                from:
                    #"{"jsonrpc":"2.0","id":"ready-1","method":"bridge.ready","params":{},"extra":true}"#
            ) == .invalid(id: "ready-1", message: "Invalid request"))
    }
}
