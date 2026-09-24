import Foundation

extension BridgeProductFileSourceIdentity {
    init(
        collectionToken: String,
        rootRevisionToken: String?,
        sourceCursor: String,
        sourceId: String,
        subscriptionGeneration: Int
    ) throws {
        try BridgeProductContractDecoding.validateOpaqueReference(collectionToken, codingPath: [])
        if let rootRevisionToken {
            try BridgeProductContractDecoding.validateOpaqueReference(rootRevisionToken, codingPath: [])
        }
        try BridgeProductContractDecoding.validateOpaqueReference(sourceCursor, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(sourceId, codingPath: [])
        try BridgeProductContractDecoding.validateNonnegative(
            subscriptionGeneration,
            name: "subscriptionGeneration",
            codingPath: []
        )
        self.collectionToken = collectionToken
        self.rootRevisionToken = rootRevisionToken
        self.sourceCursor = sourceCursor
        self.sourceId = sourceId
        self.subscriptionGeneration = subscriptionGeneration
    }
}

extension BridgeProductReviewMetadataEvent {
    init(
        generation: Int,
        packageId: String,
        publicationId: UUID,
        revision: Int,
        sourceIdentity: String
    ) throws {
        self = .sourceAccepted(
            BridgeProductReviewSourceAcceptedEvent(
                identity: try BridgeProductReviewMetadataIdentity(
                    generation: generation,
                    packageId: packageId,
                    publicationId: publicationId,
                    revision: revision,
                    sourceIdentity: sourceIdentity
                )
            )
        )
    }
}

extension BridgeProductFileMetadataEvent {
    init(source: BridgeProductFileSourceIdentity) {
        self = .sourceAccepted(.init(source: source))
    }
}
