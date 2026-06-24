import Foundation

struct BridgeReviewChangesetClusterMetadata: Codable, Equatable, Sendable {
    let clusterId: String
    let sourceId: String
    let algorithm: String
    let lifecycle: String
    let confidence: String
    let baselineCursor: String?
    let headCursor: String?
    let baselineRef: String?
    let headRef: String?
    let fromUnixMilliseconds: Int?
    let toUnixMilliseconds: Int?
    let includedPathHints: [String]?
    let groupingReason: String?
    let limitations: [String]?
}

struct BridgeReviewSnapshotPackageIdentity: Codable, Equatable, Sendable {
    let packageId: String
    let sourceIdentity: String
    let generation: Int
    let revision: Int
    let rootDescriptor: BridgeAttachedResourceDescriptor
    let contentDescriptors: [BridgeAttachedResourceDescriptor]
    let changesetCluster: BridgeReviewChangesetClusterMetadata?
}

struct BridgeReviewSnapshotFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let package: BridgeReviewSnapshotPackageIdentity

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        package: BridgeReviewSnapshotPackageIdentity
    ) {
        self.kind = "snapshot"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.snapshot"
        self.package = package
    }
}

struct BridgeReviewDeltaFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let packageId: String
    let fromRevision: Int
    let toRevision: Int
    let operationsDescriptor: BridgeAttachedResourceDescriptor
    let contentDescriptors: [BridgeAttachedResourceDescriptor]

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        packageId: String,
        fromRevision: Int,
        toRevision: Int,
        operationsDescriptor: BridgeAttachedResourceDescriptor,
        contentDescriptors: [BridgeAttachedResourceDescriptor]
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.delta"
        self.packageId = packageId
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.operationsDescriptor = operationsDescriptor
        self.contentDescriptors = contentDescriptors
    }
}

struct BridgeReviewInvalidationFrame: Codable, Equatable, Sendable {
    struct Invalidation: Codable, Equatable, Sendable {
        let scope: String
        let itemIds: [String]?
        let pathHints: [String]?
        let reason: String
    }

    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let invalidation: Invalidation

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        invalidation: Invalidation
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.invalidate"
        self.invalidation = invalidation
    }
}

struct BridgeReviewResetFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let reason: String
    let sourceIdentity: String
    let packageId: String?
    let replacementDescriptor: BridgeAttachedResourceDescriptor?

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        reason: String,
        sourceIdentity: String,
        packageId: String?,
        replacementDescriptor: BridgeAttachedResourceDescriptor?
    ) {
        self.kind = "reset"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.reset"
        self.reason = reason
        self.sourceIdentity = sourceIdentity
        self.packageId = packageId
        self.replacementDescriptor = replacementDescriptor
    }
}

enum BridgeReviewProtocolFrame: Encodable, Equatable, Sendable {
    case snapshot(BridgeReviewSnapshotFrame)
    case delta(BridgeReviewDeltaFrame)
    case invalidation(BridgeReviewInvalidationFrame)
    case reset(BridgeReviewResetFrame)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .snapshot(let frame):
            try frame.encode(to: encoder)
        case .delta(let frame):
            try frame.encode(to: encoder)
        case .invalidation(let frame):
            try frame.encode(to: encoder)
        case .reset(let frame):
            try frame.encode(to: encoder)
        }
    }
}
