import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeSchemeHandlerAppAssetTests {
    @Test
    func test_appRoute_servesCommWorkerAssetFromExplicitAppRoot() async throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-bridge-app-assets-\(UUID().uuidString)")
        let assetsRoot = fixtureRoot.appending(path: "assets")
        try FileManager.default.createDirectory(at: assetsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        try Data(
            "bridgeCommWorker.bootstrap mainToServerWorker".utf8
        ).write(to: assetsRoot.appending(path: "bridge-comm-worker.js"))
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            appRootURL: fixtureRoot
        )
        let request = URLRequest(
            url: URL(string: "agentstudio://app/assets/bridge-comm-worker.js")!)

        // Act
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

        // Assert
        let source = try #require(String(data: data, encoding: .utf8))
        #expect(response?.mimeType == "application/javascript")
        #expect(source.contains("bridgeCommWorker.bootstrap"))
        #expect(source.contains("mainToServerWorker"))
    }
}
