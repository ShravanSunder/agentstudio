import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewFoundationContractTests {
    @Test("valid bridge review package fixture decodes and round trips")
    func validBridgeReviewPackageFixtureDecodesAndRoundTrips() throws {
        let package = try decodeFixture(
            BridgeReviewPackage.self,
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
        )

        #expect(package.schemaVersion == 1)
        #expect(package.reviewGeneration == 42)
        #expect(package.revision == 1)
        #expect(package.baseEndpoint.kind == .gitRef)
        #expect(package.headEndpoint.kind == .promptCheckpoint)
        #expect(package.orderedItemIds == ["item-file-source-1"])
        #expect(package.itemsById["item-file-source-1"]?.fileClass == .source)
        #expect(package.itemsById["item-file-generated-1"]?.isHiddenByDefault == true)
        #expect(package.itemsById["item-file-source-1"]?.contentRoles.base?.handleId == "handle-source-base")
        #expect(package.itemsById["item-file-source-1"]?.contentRoles.head?.handleId == "handle-source-head")
        #expect(package.itemsById["item-file-generated-1"]?.contentRoles.head?.handleId == "handle-generated-head")
        try assertRoundTrip(package)
    }

    @Test("valid bridge review checkpoint fixture decodes and round trips")
    func validBridgeReviewCheckpointFixtureDecodesAndRoundTrips() throws {
        let checkpoint = try decodeFixture(
            BridgeReviewCheckpoint.self,
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-review-checkpoint.json"
        )

        #expect(checkpoint.checkpointKind == .prompt)
        #expect(checkpoint.reviewGeneration == 42)
        #expect(checkpoint.eventSequenceStart == 100)
        #expect(checkpoint.eventSequenceEnd == 125)
        #expect(checkpoint.promptId == "prompt-123")
        try assertRoundTrip(checkpoint)
    }

    @Test("time window query fixture decodes as review query")
    func timeWindowQueryFixtureDecodesAsReviewQuery() throws {
        let query = try decodeFixture(
            BridgeReviewQuery.self,
            relativePath: "Tests/BridgeContractFixtures/edge/bridge-review-query-time-window.json"
        )

        #expect(query.grouping.kind == .timeWindow)
        #expect(query.provenanceFilter.createdAfterUnixMilliseconds == 1_780_000_000_000)
        #expect(query.provenanceFilter.createdBeforeUnixMilliseconds == 1_780_001_800_000)
        #expect(query.viewFilter.includedFileClasses == [.source, .test])
        #expect(query.viewFilter.excludedFileClasses == [.generated, .vendor])
        try assertRoundTrip(query)
    }

    @Test("valid bridge review delta fixture decodes and round trips")
    func validBridgeReviewDeltaFixtureDecodesAndRoundTrips() throws {
        let delta = try decodeFixture(
            BridgeReviewDelta.self,
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-review-delta.json"
        )

        #expect(delta.packageId == "package-42")
        #expect(delta.reviewGeneration == 42)
        #expect(delta.operations.removeItems == ["item-file-generated-1"])
        #expect(delta.operations.updateGroups == nil)
        try assertRoundTrip(delta)
    }

    @Test("bridge content handle preserves inexact size through codable round trip")
    func bridgeContentHandlePreservesInexactSizeThroughCodableRoundTrip() throws {
        let handle = BridgeContentHandle(
            handleId: "handle-source-base",
            itemId: "item-source",
            role: .base,
            endpointId: "baseline",
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("old source"),
            contentHashAlgorithm: "sha256",
            cacheKey: "baseline:item-source:base",
            mimeType: "text/plain",
            language: nil,
            sizeBytes: 12,
            sizeBytesIsExact: false,
            isBinary: false
        )

        let encoded = try JSONEncoder().encode(handle)
        let decoded = try JSONDecoder().decode(BridgeContentHandle.self, from: encoded)

        #expect(decoded == handle)
        #expect(decoded.sizeBytesIsExact == false)
    }

    @Test("bridge review package fixture missing generation is rejected")
    func bridgeReviewPackageFixtureMissingGenerationIsRejected() throws {
        let data = try fixtureData(
            relativePath: "Tests/BridgeContractFixtures/invalid/bridge-review-package-missing-generation.json"
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeReviewPackage.self, from: data)
        }
    }

    private func decodeFixture<TDecoded: Decodable>(
        _ type: TDecoded.Type,
        relativePath: String
    ) throws -> TDecoded {
        let data = try fixtureData(relativePath: relativePath)
        return try JSONDecoder().decode(type, from: data)
    }

    private func fixtureData(relativePath: String) throws -> Data {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try Data(contentsOf: projectRoot.appending(path: relativePath))
    }

    private func assertRoundTrip<TValue: Codable & Equatable>(_ value: TValue) throws {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TValue.self, from: encoded)
        #expect(decoded == value)
    }
}
