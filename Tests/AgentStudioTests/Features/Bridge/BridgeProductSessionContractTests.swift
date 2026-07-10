import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductSessionContractTests {
    @Test("shared product-session corpus decodes strictly in Swift")
    func sharedProductSessionCorpusDecodesStrictlyInSwift() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )

        #expect(try #require(corpus["wireVersion"] as? Int) == BridgeProductWireContract.version)
        let bootstrapObject = try #require(corpus["bootstrap"] as? [String: Any])
        let bootstrap = try #require(
            decodeAndVerifyRoundTrips(BridgeProductSessionBootstrap.self, from: [bootstrapObject]).first
        )
        let requests = try decodeAndVerifyRoundTrips(
            BridgeProductControlRequest.self,
            from: try fixtureArray(named: "requests", in: corpus)
        )
        let responses = try decodeAndVerifyRoundTrips(
            BridgeProductControlResponse.self,
            from: try fixtureArray(named: "responses", in: corpus)
        )
        let streamFrames = try decodeAndVerifyRoundTrips(
            BridgeProductStreamFrame.self,
            from: try fixtureArray(named: "streamFrames", in: corpus)
        )
        let resourceRequests = try decodeAndVerifyRoundTrips(
            BridgeProductResourceRequestIdentity.self,
            from: try fixtureArray(named: "resourceRequests", in: corpus)
        )

        #expect(
            requests.map(\.kind) == [
                "workerSession.open",
                "product.command",
                "stream.open",
                "stream.cancel",
                "workerSession.resync",
            ])
        #expect(
            responses.map(\.kind) == [
                "workerSession.accepted",
                "command.accepted",
                "stream.cancelled",
                "request.error",
            ])
        #expect(
            streamFrames.map(\.kind) == [
                "stream.accepted",
                "stream.data",
                "stream.reset",
                "stream.end",
                "stream.error",
            ])
        #expect(resourceRequests.count == 1)
        #expect(resourceRequests[0].resourceRequestId == "resource-request-1")
        #expect(resourceRequests[0].resourceKind == .fileContent)
        #expect(resourceRequests[0].resourceRef == "file-content-1")
        #expect(resourceRequests[0].maximumBytes == BridgeProductWireContract.maximumResourceBytes)
        #expect(bootstrap.productCapabilityBytes.count == BridgeProductWireContract.capabilityByteLength)

        for capabilityCase in try fixtureArray(named: "capabilityHeaderCases", in: corpus) {
            let byteValues = try #require(capabilityCase["bytes"] as? [Int])
            let capabilityBytes = try byteValues.map { try #require(UInt8(exactly: $0)) }
            let expectedHeader = try #require(capabilityCase["encoded"] as? String)
            #expect(try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes) == expectedHeader)
            #expect(!expectedHeader.contains("+"))
            #expect(!expectedHeader.contains("/"))
            #expect(!expectedHeader.contains("="))
        }
    }

    @Test("product-session bootstrap rejects incomplete capability and route drift")
    func productSessionBootstrapRejectsIncompleteCapabilityAndRouteDrift() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let bootstrap = try #require(corpus["bootstrap"] as? [String: Any])

        var shortCapabilityBootstrap = bootstrap
        let capabilityBytes = try #require(bootstrap["productCapabilityBytes"] as? [Int])
        shortCapabilityBootstrap["productCapabilityBytes"] = Array(capabilityBytes.dropLast())
        #expect(throws: (any Error).self) {
            _ = try decode(BridgeProductSessionBootstrap.self, from: shortCapabilityBootstrap)
        }

        var routeDriftBootstrap = bootstrap
        var routes = try #require(bootstrap["routes"] as? [String: Any])
        routes["stream"] = ["method": "POST", "url": "agentstudio://rpc/legacy-stream"]
        routeDriftBootstrap["routes"] = routes
        #expect(throws: (any Error).self) {
            _ = try decode(BridgeProductSessionBootstrap.self, from: routeDriftBootstrap)
        }
    }

    @Test("shared hostile product-session corpus is rejected at each Swift boundary")
    func sharedHostileProductSessionCorpusIsRejectedAtEachSwiftBoundary() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/invalid/bridge-product-session-corpus.json"
        )
        let hostileCases = try fixtureArray(named: "cases", in: corpus)

        for hostileCase in hostileCases {
            let contract = try #require(hostileCase["contract"] as? String)
            let value = try #require(hostileCase["value"] as? [String: Any])
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])

            switch contract {
            case "request":
                #expect(throws: (any Error).self) {
                    _ = try JSONDecoder().decode(BridgeProductControlRequest.self, from: data)
                }
            case "response":
                #expect(throws: (any Error).self) {
                    _ = try JSONDecoder().decode(BridgeProductControlResponse.self, from: data)
                }
            case "streamFrame":
                #expect(throws: (any Error).self) {
                    _ = try JSONDecoder().decode(BridgeProductStreamFrame.self, from: data)
                }
            case "resourceRequest":
                #expect(throws: (any Error).self) {
                    _ = try JSONDecoder().decode(BridgeProductResourceRequestIdentity.self, from: data)
                }
            default:
                Issue.record("Unknown hostile product-session contract: \(contract)")
            }
        }
    }

    private func decodeAndVerifyRoundTrips<CodableValue: Codable>(
        _ type: CodableValue.Type,
        from objects: [[String: Any]]
    ) throws -> [CodableValue] {
        try objects.map { object in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let value = try JSONDecoder().decode(type, from: data)
            let encodedData = try JSONEncoder().encode(value)
            let encodedObject = try #require(
                JSONSerialization.jsonObject(with: encodedData) as? NSDictionary
            )
            #expect(encodedObject.isEqual(to: object))
            return value
        }
    }

    private func decode<CodableValue: Codable>(
        _ type: CodableValue.Type,
        from object: [String: Any]
    ) throws -> CodableValue {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(type, from: data)
    }

    private func fixtureArray(
        named name: String,
        in object: [String: Any]
    ) throws -> [[String: Any]] {
        try #require(object[name] as? [[String: Any]])
    }

    private func fixtureJSONObject(relativePath: String) throws -> [String: Any] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let data = try Data(contentsOf: projectRoot.appending(path: relativePath))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
