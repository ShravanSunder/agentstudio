import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product metadata catalog transfer contracts")
struct BridgeProductMetadataCatalogTransferContractTests {
    @Test("begin window and commit round trip with strict phase members")
    func phasesRoundTrip() throws {
        // Arrange
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let phases: [BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>] = [
            .begin(
                transferID: transferID,
                catalogRevision: 7,
                expectedEntryCount: 2
            ),
            .window(
                transferID: transferID,
                catalogRevision: 7,
                windowOrdinal: 0,
                entries: [.init(identifier: "one"), .init(identifier: "two")]
            ),
            .commit(
                transferID: transferID,
                catalogRevision: 7,
                windowCount: 1,
                entryCount: 2
            ),
        ]

        // Act / Assert
        for phase in phases {
            let encoded = try JSONEncoder.bridgeProductSorted.encode(phase)
            #expect(
                try BridgeProductStrictJSON.decode(
                    BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.self,
                    from: encoded
                ) == phase
            )
        }
    }

    @Test("an empty catalog is begin then commit without an empty window")
    func emptyCatalogContract() throws {
        // Arrange
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let begin = BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.begin(
            transferID: transferID,
            catalogRevision: 3,
            expectedEntryCount: 0
        )
        let commit = BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.commit(
            transferID: transferID,
            catalogRevision: 3,
            windowCount: 0,
            entryCount: 0
        )

        // Act / Assert
        #expect(begin.expectedEntryCount == 0)
        #expect(commit.windowCount == 0)
        #expect(commit.entryCount == 0)
        #expect(throws: (any Error).self) {
            _ = try BridgeProductStrictJSON.decode(
                BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.self,
                from: Data(
                    """
                    {"catalogRevision":3,"entries":[],"kind":"catalog.window","transferId":"\(transferID)","windowOrdinal":0}
                    """.utf8
                )
            )
        }
    }

    @Test("unknown and phase-inappropriate members are rejected")
    func unknownMembersAreRejected() throws {
        // Arrange
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let invalidBodies = [
            """
            {"catalogRevision":1,"expectedEntryCount":0,"kind":"catalog.begin","transferId":"\(transferID)","unknown":true}
            """,
            """
            {"catalogRevision":1,"entryCount":0,"entries":[],"kind":"catalog.commit","transferId":"\(transferID)","windowCount":0}
            """,
        ]

        // Act / Assert
        for body in invalidBodies {
            #expect(throws: (any Error).self) {
                _ = try BridgeProductStrictJSON.decode(
                    BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.self,
                    from: Data(body.utf8)
                )
            }
        }
    }

    @Test("entry-count surfaces reject more than the product catalog limit")
    func entryCountSurfacesRejectOverLimit() throws {
        // Arrange
        let transferID = UUIDv7.generate().uuidString.lowercased()
        let excessiveCount = BridgeProductMetadataCatalogCapacity.maximumEntryCount + 1
        let excessiveEntries = Array(
            repeating: CatalogTransferFixtureEntry(identifier: "entry"),
            count: excessiveCount
        )

        // Act / Assert
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder.bridgeProductSorted.encode(
                BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.begin(
                    transferID: transferID,
                    catalogRevision: 1,
                    expectedEntryCount: excessiveCount
                )
            )
        }
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder.bridgeProductSorted.encode(
                BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.window(
                    transferID: transferID,
                    catalogRevision: 1,
                    windowOrdinal: 0,
                    entries: excessiveEntries
                )
            )
        }
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder.bridgeProductSorted.encode(
                BridgeProductMetadataCatalogTransfer<CatalogTransferFixtureEntry>.commit(
                    transferID: transferID,
                    catalogRevision: 1,
                    windowCount: 1,
                    entryCount: excessiveCount
                )
            )
        }
    }
}

private struct CatalogTransferFixtureEntry: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case identifier = "itemId"
    }

    let identifier: String
}
