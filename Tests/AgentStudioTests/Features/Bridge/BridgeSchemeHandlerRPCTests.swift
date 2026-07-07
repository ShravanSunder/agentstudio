import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeSchemeHandlerRPCTests {
    @MainActor
    private final class RPCDispatcherSpy: BridgeSchemeRPCDispatching {
        private(set) var receivedJSON: [String] = []
        var responseJSON: String?

        func dispatchBridgeSchemeRPC(json: String) async -> String? {
            receivedJSON.append(json)
            return responseJSON
        }
    }

    @Test
    func rpcCommandRoute_isClassifiedAsPostRoute() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://rpc/command")

        #expect(result != .invalid)
    }

    @MainActor
    @Test
    func rpcCommandRoute_postsJSONBodyToDispatcherAndReturnsJSONResponse() async throws {
        let dispatcher = RPCDispatcherSpy()
        dispatcher.responseJSON = #"{"jsonrpc":"2.0","id":"cmd-1","result":{}}"#
        let handler = BridgeSchemeHandler(paneId: UUID(), rpcDispatcher: dispatcher)
        var request = URLRequest(url: URL(string: "agentstudio://rpc/command")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            #"{"jsonrpc":"2.0","id":"cmd-1","method":"review.markFileViewed","params":{"fileId":"item-1"}}"#.utf8)

        var response: HTTPURLResponse?
        var body = Data()
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                response = emittedResponse as? HTTPURLResponse
            case .data(let chunk):
                body.append(chunk)
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(response?.value(forHTTPHeaderField: "Access-Control-Allow-Methods") == "OPTIONS, POST")
        #expect(response?.mimeType == "application/json")
        #expect(
            dispatcher.receivedJSON == [
                #"{"jsonrpc":"2.0","id":"cmd-1","method":"review.markFileViewed","params":{"fileId":"item-1"}}"#
            ])
        #expect(String(data: body, encoding: .utf8) == #"{"jsonrpc":"2.0","id":"cmd-1","result":{}}"#)
    }
}
