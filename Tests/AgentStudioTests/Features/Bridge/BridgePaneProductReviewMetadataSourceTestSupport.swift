import Foundation
import Testing

@testable import AgentStudio

struct ReviewWindowPayload {
    let isSnapshot: Bool
    let itemStartIndex: Int
    let itemFinalWindow: Bool
    let itemMetadata: [BridgeProductReviewItemMetadataValue]
    let treeStartIndex: Int
    let treeFinalWindow: Bool
    let treeRows: [BridgeProductReviewTreeRowValue]
}

func reviewWindowPayload(_ event: BridgeProductReviewMetadataEvent) throws -> ReviewWindowPayload {
    switch event {
    case .snapshot(let snapshot):
        ReviewWindowPayload(
            isSnapshot: true,
            itemStartIndex: snapshot.itemWindow.startIndex,
            itemFinalWindow: snapshot.itemWindow.finalWindow,
            itemMetadata: snapshot.itemMetadata,
            treeStartIndex: snapshot.treeWindow.startIndex,
            treeFinalWindow: snapshot.treeWindow.finalWindow,
            treeRows: snapshot.treeRows
        )
    case .window(let window):
        ReviewWindowPayload(
            isSnapshot: false,
            itemStartIndex: window.itemWindow.startIndex,
            itemFinalWindow: window.itemWindow.finalWindow,
            itemMetadata: window.itemMetadata,
            treeStartIndex: window.treeWindow.startIndex,
            treeFinalWindow: window.treeWindow.finalWindow,
            treeRows: window.treeRows
        )
    default:
        throw ReviewMetadataSourceTestError.unexpectedEvent
    }
}

func assertContiguousReviewWindows(
    _ windows: [ReviewWindowPayload],
    package: BridgeReviewPackage,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    var nextItemIndex = 0
    var nextTreeIndex = 0
    for window in windows {
        #expect(window.itemStartIndex == nextItemIndex, sourceLocation: sourceLocation)
        #expect(window.treeStartIndex == nextTreeIndex, sourceLocation: sourceLocation)
        nextItemIndex += window.itemMetadata.count
        nextTreeIndex += window.treeRows.count
    }
    #expect(nextItemIndex == package.orderedItemIds.count, sourceLocation: sourceLocation)
    #expect(nextTreeIndex >= package.orderedItemIds.count, sourceLocation: sourceLocation)
}

enum ReviewMetadataSourceTestError: Error {
    case unexpectedEvent
}

func deliverReviewPackage(
    _ package: BridgeReviewPackage,
    publicationId: UUID = reviewMetadataTestPublicationId,
    through source: BridgePaneProductReviewMetadataSource,
    productAdmission: BridgeProductAdmissionContext
) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
    let reservation = try await source.reserve(
        package: package,
        publicationId: publicationId,
        productAdmission: productAdmission
    )
    return try await source.deliver(
        package: package,
        reservation: reservation,
        productAdmission: productAdmission
    )
}

func deliveredReviewReceipt(
    _ outcome: BridgePaneProductReviewMetadataPublicationOutcome
) throws -> BridgeReviewMetadataPublicationReceipt {
    guard case .delivered(let receipt) = outcome else {
        throw ReviewMetadataSourceTestError.unexpectedEvent
    }
    return receipt
}

func reviewMetadataEnqueueResult(
    _ event: BridgeProductReviewMetadataEvent,
    sequence: Int
) throws -> BridgeProductProducerEnqueueResult {
    .enqueued(
        BridgeProductQueuedProducerFrame(
            data: try JSONEncoder().encode(event),
            sequence: sequence,
            terminal: false,
            requiredOpening: false
        ))
}

func reviewIdentity(for package: BridgeReviewPackage) -> BridgeProductReviewMetadataIdentity {
    try! BridgeProductReviewMetadataIdentity(
        generation: package.reviewGeneration.rawValue,
        packageId: package.packageId,
        publicationId: reviewMetadataTestPublicationId,
        revision: package.revision,
        sourceIdentity: package.query.queryId
    )
}

var reviewMetadataTestPublicationId: UUID {
    UUID(uuidString: "11111111-1111-7111-8111-111111111111")!
}
