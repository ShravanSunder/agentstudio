import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeSchemeHandlerAppAssetTests {
    @Test
    func test_appRoute_servesPackagedCommWorkerAsset() async throws {
        let handler = BridgeSchemeHandler(paneId: UUID())
        let request = URLRequest(
            url: URL(string: "agentstudio://app/assets/bridge-comm-worker.js")!)

        var response: URLResponse?
        var data = Data()
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                response = emittedResponse
            case .data(let chunk):
                data.append(chunk)
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        let source = try #require(String(data: data, encoding: .utf8))
        #expect(response?.mimeType == "application/javascript")
        #expect(source.contains("bridgeCommWorker.bootstrap"))
        #expect(source.contains("mainToServerWorker"))
    }
}
