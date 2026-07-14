import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product startup transcript")
struct BridgeProductStartupTranscriptTests {
    private static let validFixturePath =
        "Tests/BridgeContractFixtures/valid/bridge-product-startup-transcript.json"
    private static let invalidFixturePath =
        "Tests/BridgeContractFixtures/invalid/bridge-product-startup-transcript.json"
    private static let validMirrorPath =
        "BridgeWeb/src/test-fixtures/bridge-contract-fixtures/valid/bridge-product-startup-transcript.json"
    private static let invalidMirrorPath =
        "BridgeWeb/src/test-fixtures/bridge-contract-fixtures/invalid/bridge-product-startup-transcript.json"
    private static let validFixtureSHA256 =
        "9dbb1c5d33f832e0c76b09859fdc9aed6561256033b6acede000df4f2a774112"
    private static let invalidFixtureSHA256 =
        "78da34fabc8fdfeb2316df0b21e819691ea2bb4e861a74cbee3270231d6494c8"

    @Test("Swift source fixtures and TypeScript mirrors have frozen byte identity")
    func fixturesHaveFrozenByteIdentity() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixturePairs = [
            (Self.validFixturePath, Self.validMirrorPath, Self.validFixtureSHA256),
            (Self.invalidFixturePath, Self.invalidMirrorPath, Self.invalidFixtureSHA256),
        ]

        // Act
        let identities = try fixturePairs.map { sourcePath, mirrorPath, expectedSHA256 in
            let sourceBytes = try Data(contentsOf: projectRoot.appending(path: sourcePath))
            let mirrorBytes = try Data(contentsOf: projectRoot.appending(path: mirrorPath))
            return (sourceBytes, mirrorBytes, expectedSHA256, sha256Hex(sourceBytes))
        }

        // Assert
        for (sourceBytes, mirrorBytes, expectedSHA256, observedSHA256) in identities {
            #expect(sourceBytes == mirrorBytes)
            #expect(observedSHA256 == expectedSHA256)
        }
    }

    @Test("already-supported startup and event structures decode and round-trip")
    func supportedTranscriptStructuresDecodeAndRoundTrip() throws {
        // Arrange
        let fixture = try loadFixture(relativePath: Self.validFixturePath)
        let transcript = try fixtureArray(named: "transcript", in: fixture)

        // Act / Assert
        #expect(transcript.count == 27)
        for entry in transcript {
            let codec = try #require(entry["codec"] as? String)
            let name = try #require(entry["name"] as? String)
            let value = try #require(entry["value"] as? [String: Any])
            switch codec {
            case "contentHeader":
                try assertRoundTrip(BridgeProductContentHeader.self, object: value, name: name)
            case "contentRequest":
                try assertRoundTrip(BridgeProductContentRequest.self, object: value, name: name)
            case "controlRequest":
                try assertRoundTrip(BridgeProductControlRequest.self, object: value, name: name)
            case "controlResponse":
                try assertRoundTrip(BridgeProductControlResponse.self, object: value, name: name)
            case "metadataFrame":
                try assertRoundTrip(BridgeProductMetadataFrame.self, object: value, name: name)
            case "metadataStreamRequest":
                try assertRoundTrip(
                    BridgeProductMetadataStreamRequest.self,
                    object: value,
                    name: name
                )
            default:
                Issue.record("Unsupported startup transcript codec: \(codec)")
            }
        }
    }

    @Test("Review interest transition hashes derive through production state")
    func reviewInterestTransitionHashesDeriveThroughProductionState() throws {
        // Arrange
        let fixture = try loadFixture(relativePath: Self.validFixturePath)
        let updateCommand = try decodeTranscriptValue(
            BridgeProductControlRequest.self,
            named: "review-selection-demand",
            in: fixture
        )
        let updateResponse = try decodeTranscriptValue(
            BridgeProductControlResponse.self,
            named: "review-selection-demand-accepted",
            in: fixture
        )
        let committedFrame = try decodeTranscriptValue(
            BridgeProductMetadataFrame.self,
            named: "review-selection-demand-committed",
            in: fixture
        )
        let cancelledFrame = try decodeTranscriptValue(
            BridgeProductMetadataFrame.self,
            named: "review-subscription-cancelled-frame",
            in: fixture
        )
        guard case .subscriptionUpdateBatch(let updateRequest) = updateCommand,
            case .subscriptionUpdateBatchAccepted(let acceptedResponse) = updateResponse,
            case .subscriptionInterestsCommitted(let committed) = committedFrame,
            case .subscriptionCancelled(let cancelled) = cancelledFrame
        else {
            Issue.record("Review startup transcript does not contain its typed interest transitions")
            return
        }

        // Act
        let emptyState = BridgeProductSubscriptionState.emptyInterestState(for: .reviewMetadata)
        let candidateState = try BridgeProductSubscriptionInterestMutation.apply(
            [updateRequest.delta],
            to: emptyState,
            subscriptionKind: .reviewMetadata
        )
        let derivedSHA256 = try candidateState.sha256Hex()

        // Assert
        #expect(try emptyState.sha256Hex() == updateRequest.baseInterestSha256)
        #expect(
            [
                updateRequest.targetInterestSha256,
                acceptedResponse.targetInterestSha256,
                committed.identity.subscriptionIdentity.interestSha256,
                cancelled.identity.subscriptionIdentity.interestSha256,
            ].allSatisfy { $0 == derivedSHA256 }
        )
    }

    @Test("observation identities and lifecycle outcomes are frozen")
    func observationIdentitiesAndLifecycleOutcomesAreFrozen() throws {
        // Arrange
        let fixture = try loadFixture(relativePath: Self.validFixturePath)
        let observationCases = try fixtureArray(named: "observationCases", in: fixture)
        let lifecycle = try #require(fixture["lifecycleExpectations"] as? [String: Any])
        let zeroResidue = try #require(lifecycle["zeroResidue"] as? [String: Any])

        // Act
        let metadataCase = try #require(
            observationCases.first { observationCase in
                (observationCase["request"] as? [String: Any])?["streamKind"] as? String
                    == "metadata"
            }
        )
        let contentCase = try #require(
            observationCases.first { observationCase in
                (observationCase["request"] as? [String: Any])?["streamKind"] as? String
                    == "content"
            }
        )
        let metadataKeys = Set(try #require(metadataCase["request"] as? [String: Any]).keys)
        let contentKeys = Set(try #require(contentCase["request"] as? [String: Any]).keys)
        let dispositions = Set(
            try observationCases.map { try #require($0["expectedDisposition"] as? String) }
        )

        // Assert
        #expect(observationCases.count == 16)
        #expect(
            metadataKeys == [
                "kind", "metadataStreamId", "paneSessionId", "streamKind", "streamSequence",
                "wireVersion", "workerInstanceId",
            ]
        )
        #expect(
            contentKeys == [
                "contentRequestId", "contentSequence", "kind", "leaseId", "paneSessionId",
                "streamKind", "wireVersion", "workerInstanceId",
            ]
        )
        #expect(
            dispositions == [
                "accepted", "idempotentReplay", "rejectedChangedReuse",
                "rejectedForeignIdentity", "rejectedPostTerminal", "rejectedSequenceGap",
                "rejectedStaleWorker",
            ]
        )
        #expect(zeroResidue.count == 7)
        #expect(zeroResidue.values.allSatisfy { ($0 as? Int) == 0 })
    }

    @Test("metadata observation decodes through the current command package")
    func metadataObservationDecodesThroughCurrentCommandPackage() throws {
        // Arrange
        let fixture = try loadFixture(relativePath: Self.validFixturePath)
        let observationCases = try fixtureArray(named: "observationCases", in: fixture)
        let metadataCase = try #require(
            observationCases.first { observationCase in
                (observationCase["request"] as? [String: Any])?["streamKind"] as? String
                    == "metadata"
            }
        )
        let request = try #require(metadataCase["request"] as? [String: Any])

        // Act
        let package = try decodeCommandPackage(request)

        // Assert
        guard case .metadataFrameAcknowledgement = package else {
            Issue.record("Metadata observation did not decode as an acknowledgement")
            return
        }
    }

    @Test("content accepted data and end observations decode through the command package")
    func contentFrameObservationsDecodeThroughCommandPackage() throws {
        // Arrange
        let fixture = try loadFixture(relativePath: Self.validFixturePath)
        let observationCases = try fixtureArray(named: "observationCases", in: fixture)
        let requiredCaseNames = [
            "content-accepted-sequence-zero",
            "content-data-sequence-one",
            "content-end-sequence-two",
        ]

        // Act
        let requiredCases = try requiredCaseNames.map { requiredName in
            try #require(
                observationCases.first { $0["name"] as? String == requiredName },
                "Missing required content observation \(requiredName)"
            )
        }

        // Assert
        for requiredCase in requiredCases {
            let name = try #require(requiredCase["name"] as? String)
            let request = try #require(requiredCase["request"] as? [String: Any])
            let package = try decodeCommandPackage(request)
            guard case .contentFrameAcknowledgement = package else {
                Issue.record("\(name) did not decode as a content frame acknowledgement")
                continue
            }
        }
    }

    @Test("structurally hostile observation bodies are rejected")
    func structurallyHostileObservationBodiesAreRejected() throws {
        // Arrange
        let fixture = try loadFixture(relativePath: Self.invalidFixturePath)
        let invalidCases = try fixtureArray(named: "cases", in: fixture)

        // Act
        let acceptedCases = invalidCases.compactMap { fixtureCase -> String? in
            guard
                let name = fixtureCase["name"] as? String,
                let request = fixtureCase["request"] as? [String: Any]
            else { return "malformed-fixture-case" }
            return (try? decodeCommandPackage(request)) == nil ? nil : name
        }

        // Assert
        #expect(invalidCases.count == 10)
        #expect(acceptedCases.isEmpty)
    }

    private func loadFixture(relativePath: String) throws -> [String: Any] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let bytes = try Data(contentsOf: projectRoot.appending(path: relativePath))
        return try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func fixtureArray(
        named name: String,
        in fixture: [String: Any]
    ) throws -> [[String: Any]] {
        try #require(fixture[name] as? [[String: Any]])
    }

    private func assertRoundTrip<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any],
        name: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try BridgeProductStrictJSON.decode(type, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(encodedObject.isEqual(to: object), Comment(rawValue: name))
    }

    private func decodeTranscriptValue<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        named name: String,
        in fixture: [String: Any]
    ) throws -> DecodedValue {
        let transcript = try fixtureArray(named: "transcript", in: fixture)
        let entry = try #require(transcript.first { $0["name"] as? String == name })
        let value = try #require(entry["value"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(type, from: data)
    }

    private func decodeCommandPackage(
        _ object: [String: Any]
    ) throws -> BridgeProductCommandPackage {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(BridgeProductCommandPackage.self, from: data)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
