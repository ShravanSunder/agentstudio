import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge metadata application ingress")
struct BridgeProductMetadataApplicationIngressTests {
    @Test("unknown registered kinds fail closed at cancel and active-resync ingress")
    func unknownRegisteredKindsFailClosedAtControlIngress() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let data = try Data(
            contentsOf: projectRoot.appending(
                path: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
            )
        )
        let corpus = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let requests = try #require(corpus["controlRequests"] as? [[String: Any]])

        var cancel = try #require(requests.first { $0["kind"] as? String == "subscription.cancel" })
        cancel["subscriptionKind"] = "unknown.metadata"
        #expect(decodingFails(cancel))

        var resync = try #require(requests.first { $0["kind"] as? String == "workerSession.resync" })
        var activeSubscriptions = try #require(resync["activeSubscriptions"] as? [[String: Any]])
        activeSubscriptions[0]["subscriptionKind"] = "unknown.metadata"
        resync["activeSubscriptions"] = activeSubscriptions
        #expect(decodingFails(resync))
    }

    private func decodingFails(_ object: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            _ = try BridgeProductStrictJSON.decode(BridgeProductControlRequest.self, from: data)
            return false
        } catch {
            return true
        }
    }
}
