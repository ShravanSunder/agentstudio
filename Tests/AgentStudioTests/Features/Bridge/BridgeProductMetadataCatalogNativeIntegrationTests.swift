import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product metadata catalog native integration")
struct BridgeProductMetadataCatalogNativeIntegrationTests {
    private static let sourceFixturePath =
        "Tests/BridgeContractFixtures/valid/bridge-product-metadata-catalog-transfer-corpus.json"
    private static let mirrorFixturePath =
        "BridgeWeb/src/test-fixtures/bridge-contract-fixtures/valid/bridge-product-metadata-catalog-transfer-corpus.json"

    @Test("shared Swift and TypeScript transfer corpus has identical strict wire bytes")
    func sharedTransferCorpusHasIdenticalWireBytes() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourceBytes = try Data(
            contentsOf: projectRoot.appending(path: Self.sourceFixturePath)
        )
        let mirrorBytes = try Data(
            contentsOf: projectRoot.appending(path: Self.mirrorFixturePath)
        )
        let corpus = try JSONDecoder().decode(CatalogTransferCorpus.self, from: sourceBytes)

        // Act / Assert
        #expect(sourceBytes == mirrorBytes)
        for sequence in corpus.validSequences {
            #expect(!sequence.name.isEmpty)
            for rawTransfer in sequence.transfers {
                let transfer = try BridgeProductStrictJSON.decode(
                    BridgeProductMetadataCatalogTransfer<CatalogTransferIntegrationEntry>.self,
                    from: Data(rawTransfer.utf8)
                )
                let roundTrip = try JSONEncoder.bridgeProductSorted.encode(transfer)
                let roundTripJSON = try #require(String(data: roundTrip, encoding: .utf8))
                #expect(roundTripJSON == rawTransfer)
            }
        }
    }

    @Test("shared large-catalog recipe crosses multiple bounded metadata frames")
    func sharedLargeCatalogRecipeCrossesMultipleFrames() throws {
        // Arrange
        let corpus = try loadCorpus()
        let recipe = corpus.largeCatalogRecipe
        let entries = (0..<recipe.entryCount).map { index in
            CatalogTransferIntegrationEntry(
                itemID: "item-\(index)",
                payload: String(repeating: "x", count: recipe.payloadCharacterCount)
            )
        }
        let writer = BridgeProductMetadataCatalogWriter<CatalogTransferIntegrationEntry>()

        // Act
        let transfers = try writer.preflight(
            entries: entries,
            catalogRevision: recipe.catalogRevision,
            transferID: recipe.transferID,
            makeProspectiveMetadataFrame: CatalogTransferIntegrationFrame.init(event:)
        )
        let windows = transfers.compactMap(\.windowOrdinal)

        // Assert
        #expect(windows.count == recipe.expectedWindowCount)
        #expect(windows.count > 1)
        #expect(transfers.first?.expectedEntryCount == recipe.entryCount)
        #expect(transfers.last?.entryCount == recipe.entryCount)
        for transfer in transfers {
            let body = try BridgeProductMetadataFrameCodec.encodeJSONBody(
                CatalogTransferIntegrationFrame(event: transfer)
            )
            #expect(body.count <= BridgeProductWireContract.maximumMetadataFrameBytes)
        }
    }

    private func loadCorpus() throws -> CatalogTransferCorpus {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try JSONDecoder().decode(
            CatalogTransferCorpus.self,
            from: Data(
                contentsOf: projectRoot.appending(path: Self.sourceFixturePath)
            )
        )
    }
}

private struct CatalogTransferCorpus: Decodable {
    let largeCatalogRecipe: CatalogTransferLargeRecipe
    let validSequences: [CatalogTransferSequence]
}

private struct CatalogTransferLargeRecipe: Decodable {
    let catalogRevision: Int
    let entryCount: Int
    let expectedWindowCount: Int
    let payloadCharacterCount: Int
    let transferID: String

    private enum CodingKeys: String, CodingKey {
        case catalogRevision
        case entryCount
        case expectedWindowCount
        case payloadCharacterCount
        case transferID = "transferId"
    }
}

private struct CatalogTransferSequence: Decodable {
    let name: String
    let transfers: [String]
}

private struct CatalogTransferIntegrationEntry: Codable, Equatable, Sendable {
    let itemID: String
    let payload: String

    private enum CodingKeys: String, CodingKey {
        case itemID = "itemId"
        case payload
    }
}

private struct CatalogTransferIntegrationFrame: Encodable {
    let data: CatalogTransferIntegrationData
    let kind = "subscription.data"

    init(
        event: BridgeProductMetadataCatalogTransfer<CatalogTransferIntegrationEntry>
    ) {
        data = .init(event: event)
    }
}

private struct CatalogTransferIntegrationData: Encodable {
    let event: BridgeProductMetadataCatalogTransfer<CatalogTransferIntegrationEntry>
    let subscriptionKind = "fixture.metadata"
}
