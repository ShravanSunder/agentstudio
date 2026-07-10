import Foundation

extension BridgeProductFileSourceIdentity {
    init(
        repoId: String,
        rootRevisionToken: String?,
        sourceCursor: String,
        sourceId: String,
        subscriptionGeneration: Int,
        worktreeId: String
    ) throws {
        try BridgeProductContractDecoding.validateUUID(repoId, codingPath: [])
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
        try BridgeProductContractDecoding.validateUUID(worktreeId, codingPath: [])
        self.repoId = repoId
        self.rootRevisionToken = rootRevisionToken
        self.sourceCursor = sourceCursor
        self.sourceId = sourceId
        self.subscriptionGeneration = subscriptionGeneration
        self.worktreeId = worktreeId
    }
}

extension BridgeProductReviewMetadataEvent {
    init(
        generation: Int,
        packageId: String,
        revision: Int,
        sourceIdentity: String
    ) throws {
        try BridgeProductContractDecoding.validateNonnegative(
            generation,
            name: "generation",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: [])
        try BridgeProductContractDecoding.validateNonnegative(
            revision,
            name: "revision",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: [])
        self.generation = generation
        self.packageId = packageId
        self.revision = revision
        self.sourceIdentity = sourceIdentity
    }
}

extension BridgeProductFileMetadataEvent {
    init(source: BridgeProductFileSourceIdentity) {
        self.source = source
    }
}
