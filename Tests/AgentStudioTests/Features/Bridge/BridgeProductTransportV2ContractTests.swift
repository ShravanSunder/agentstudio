import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product v2 wire contracts")
struct BridgeProductTransportV2ContractTests {
    @Test("shared startup envelope transcript round-trips without running effects")
    func sharedStartupEnvelopeTranscriptRoundTrips() throws {
        let fixture = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-startup-transcript.json"
        )
        let entries = try fixtureArray(named: "envelopeTranscript", in: fixture)
        #expect(entries.count == 4)
        for entry in entries {
            let codec = try #require(entry["codec"] as? String)
            let value = try #require(entry["value"] as? [String: Any])
            switch codec {
            case "operationAdmittedResponse":
                _ = try decodeAndVerifyRoundTrips(BridgeProductOperationAdmittedResponse.self, from: [value])
            case "operationResultRequest":
                _ = try decodeAndVerifyRoundTrips(BridgeProductOperationResultRequest.self, from: [value])
            case "operationResultResponse":
                _ = try decodeAndVerifyRoundTrips(BridgeProductOperationResultResponse.self, from: [value])
            case "operationResultAcknowledgement":
                _ = try decodeAndVerifyRoundTrips(BridgeProductOperationResultAcknowledgement.self, from: [value])
            default:
                Issue.record("Unsupported v2 startup envelope codec: \(codec)")
            }
        }
    }

    @Test("shared v2 operation and sealed-batch envelopes round-trip in Swift")
    func sharedV2TransportEnvelopesRoundTrip() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let transport = try #require(corpus["transportV2"] as? [String: Any])

        _ = try decodeAndVerifyRoundTrips(
            BridgeProductOperationAdmittedResponse.self,
            from: try fixtureArray(named: "admittedResponses", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductOperationResultRequest.self,
            from: try fixtureArray(named: "resultRequests", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductOperationResultResponse.self,
            from: try fixtureArray(named: "resultResponses", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductOperationResultAcknowledgement.self,
            from: try fixtureArray(named: "resultAcknowledgements", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductOperationResultAcknowledgedResponse.self,
            from: try fixtureArray(named: "resultAcknowledgedResponses", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductViewScopeRequest.self,
            from: try fixtureArray(named: "viewScopeRequests", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductViewResnapshotRequest.self,
            from: try fixtureArray(named: "viewResnapshotRequests", in: transport)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductViewAcknowledgementRequest.self,
            from: try fixtureArray(named: "viewAcknowledgements", in: transport)
        )
        let batches = try decodeAndVerifyRoundTrips(
            BridgeProductBatchFrame.self,
            from: try fixtureArray(named: "batchFrames", in: transport)
        )
        #expect(batches.count == 7)
    }

    @Test("shared v2 invalid envelopes fail at the same structural boundary")
    func sharedV2InvalidTransportEnvelopesFail() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/invalid/bridge-product-transport-v2-corpus.json"
        )
        for result in try fixtureArray(named: "resultResponses", in: corpus) {
            #expect(decodingFails(BridgeProductOperationResultResponse.self, object: result))
        }
        for frame in try fixtureArray(named: "batchFrames", in: corpus) {
            #expect(decodingFails(BridgeProductBatchFrame.self, object: frame))
        }
        for acknowledgement in try fixtureArray(named: "viewAcknowledgements", in: corpus) {
            #expect(decodingFails(BridgeProductViewAcknowledgementRequest.self, object: acknowledgement))
        }

        let validCorpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let transport = try #require(validCorpus["transportV2"] as? [String: Any])
        var batch = try #require(fixtureArray(named: "batchFrames", in: transport).first)
        batch["scope"] = NSNull()
        #expect(decodingFails(BridgeProductBatchFrame.self, object: batch))
    }

    private func decodeAndVerifyRoundTrips<CodableValue: Codable>(
        _ type: CodableValue.Type,
        from objects: [[String: Any]]
    ) throws -> [CodableValue] {
        try objects.map { object in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let value: CodableValue
            do {
                value = try BridgeProductStrictJSON.decode(type, from: data)
            } catch {
                let kind = String(describing: object["kind"] ?? "missing")
                let batchId = String(describing: object["batchId"] ?? "none")
                Issue.record("Failed to decode \(String(describing: type)) kind=\(kind) batchId=\(batchId): \(error)")
                throw error
            }
            let encodedData = try JSONEncoder().encode(value)
            let encodedObject = try #require(JSONSerialization.jsonObject(with: encodedData) as? NSDictionary)
            #expect(encodedObject.isEqual(to: object))
            return value
        }
    }

    private func decodingFails<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return true
        }
        do {
            _ = try BridgeProductStrictJSON.decode(type, from: data)
            return false
        } catch {
            return true
        }
    }

    private func fixtureArray(named name: String, in object: [String: Any]) throws -> [[String: Any]] {
        try #require(object[name] as? [[String: Any]])
    }

    private func fixtureJSONObject(relativePath: String) throws -> [String: Any] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let data = try Data(contentsOf: projectRoot.appending(path: relativePath))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
