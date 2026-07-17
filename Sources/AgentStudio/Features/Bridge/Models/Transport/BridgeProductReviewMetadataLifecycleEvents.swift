import Foundation

struct BridgeProductReviewDeltaEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentSources
        case eventKind
        case fromRevision
        case operations
        case summary
        case toRevision
    }

    let identity: BridgeProductReviewMetadataIdentity
    let contentSources: [BridgeProductReviewContentSourceDescriptor]
    let fromRevision: Int
    let operations: [BridgeProductReviewMetadataOperation]
    let summary: BridgeProductReviewPackageSummaryValue
    let toRevision: Int

    init(
        identity: BridgeProductReviewMetadataIdentity,
        contentSources: [BridgeProductReviewContentSourceDescriptor],
        fromRevision: Int,
        operations: [BridgeProductReviewMetadataOperation],
        summary: BridgeProductReviewPackageSummaryValue,
        toRevision: Int
    ) throws {
        self.identity = identity
        self.contentSources = contentSources
        self.fromRevision = fromRevision
        self.operations = operations
        self.summary = summary
        self.toRevision = toRevision
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try rejectReviewLifecycleEventUnknownKeys(
            from: decoder,
            additionalKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review delta event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "review.delta" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review delta kind",
                codingPath: decoder.codingPath
            )
        }
        self.identity = try BridgeProductReviewMetadataIdentity(from: decoder)
        self.contentSources = try container.decode(
            [BridgeProductReviewContentSourceDescriptor].self,
            forKey: .contentSources
        )
        self.fromRevision = try container.decode(Int.self, forKey: .fromRevision)
        self.operations = try container.decode([BridgeProductReviewMetadataOperation].self, forKey: .operations)
        self.summary = try container.decode(BridgeProductReviewPackageSummaryValue.self, forKey: .summary)
        self.toRevision = try container.decode(Int.self, forKey: .toRevision)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            contentSources.count,
            maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
            name: "contentSources",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateCollectionCount(
            operations.count,
            maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
            name: "operations",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            fromRevision,
            name: "fromRevision",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            toRevision,
            name: "toRevision",
            codingPath: codingPath
        )
        guard identity.revision == toRevision, fromRevision <= toRevision else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review metadata delta revision lineage is invalid",
                codingPath: codingPath
            )
        }
        for source in contentSources {
            guard source.packageId == identity.packageId,
                source.reviewGeneration == identity.generation,
                source.sourceIdentity == identity.sourceIdentity
            else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review content source identity does not match its delta event",
                    codingPath: codingPath
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentSources, forKey: .contentSources)
        try container.encode("review.delta", forKey: .eventKind)
        try container.encode(fromRevision, forKey: .fromRevision)
        try container.encode(operations, forKey: .operations)
        try container.encode(summary, forKey: .summary)
        try container.encode(toRevision, forKey: .toRevision)
    }
}

struct BridgeProductReviewInvalidatedEvent: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Equatable, Sendable {
        case sourceChanged
        case watchEvent
        case lineageReplaced
        case unknown
    }

    enum Scope: String, Codable, Equatable, Sendable {
        case package
        case items
        case paths
        case treeWindow
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case itemIds
        case pathHints
        case reason
        case scope
    }

    let identity: BridgeProductReviewMetadataIdentity
    let itemIds: [String]
    let pathHints: [String]
    let reason: Reason
    let scope: Scope

    init(from decoder: Decoder) throws {
        try rejectReviewLifecycleEventUnknownKeys(
            from: decoder,
            additionalKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review invalidated event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "review.invalidated" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review invalidated kind",
                codingPath: decoder.codingPath
            )
        }
        self.identity = try BridgeProductReviewMetadataIdentity(from: decoder)
        self.itemIds = try container.decode([String].self, forKey: .itemIds)
        self.pathHints = try container.decode([String].self, forKey: .pathHints)
        self.reason = try container.decode(Reason.self, forKey: .reason)
        self.scope = try container.decode(Scope.self, forKey: .scope)
        try BridgeProductContractDecoding.validateCollectionCount(
            itemIds.count,
            maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
            name: "itemIds",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateCollectionCount(
            pathHints.count,
            maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
            name: "pathHints",
            codingPath: decoder.codingPath
        )
        for itemId in itemIds {
            try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
        }
        for path in pathHints {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review.invalidated", forKey: .eventKind)
        try container.encode(itemIds, forKey: .itemIds)
        try container.encode(pathHints, forKey: .pathHints)
        try container.encode(reason, forKey: .reason)
        try container.encode(scope, forKey: .scope)
    }
}

struct BridgeProductReviewResetEvent: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Equatable, Sendable {
        case sourceChanged
        case subscriptionReset
        case providerRestart
        case authorityChanged
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case reason
    }

    let identity: BridgeProductReviewMetadataIdentity
    let reason: Reason

    init(identity: BridgeProductReviewMetadataIdentity, reason: Reason) {
        self.identity = identity
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        try rejectReviewLifecycleEventUnknownKeys(
            from: decoder,
            additionalKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review reset event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "review.reset" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review reset kind",
                codingPath: decoder.codingPath
            )
        }
        self.identity = try BridgeProductReviewMetadataIdentity(from: decoder)
        self.reason = try container.decode(Reason.self, forKey: .reason)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review.reset", forKey: .eventKind)
        try container.encode(reason, forKey: .reason)
    }
}

enum BridgeProductReviewMetadataEvent: Codable, Equatable, Sendable {
    case sourceAccepted(BridgeProductReviewSourceAcceptedEvent)
    case snapshot(BridgeProductReviewSnapshotEvent)
    case window(BridgeProductReviewWindowEvent)
    case delta(BridgeProductReviewDeltaEvent)
    case invalidated(BridgeProductReviewInvalidatedEvent)
    case reset(BridgeProductReviewResetEvent)

    private enum CodingKeys: String, CodingKey {
        case eventKind
    }

    var generation: Int {
        identity.generation
    }

    var packageId: String {
        identity.packageId
    }

    var publicationId: UUID {
        identity.publicationId
    }

    var revision: Int {
        identity.revision
    }

    var sourceIdentity: String {
        identity.sourceIdentity
    }

    private var identity: BridgeProductReviewMetadataIdentity {
        switch self {
        case .sourceAccepted(let event): event.identity
        case .snapshot(let event): event.identity
        case .window(let event): event.identity
        case .delta(let event): event.identity
        case .invalidated(let event): event.identity
        case .reset(let event): event.identity
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .eventKind) {
        case "review.sourceAccepted":
            self = .sourceAccepted(try BridgeProductReviewSourceAcceptedEvent(from: decoder))
        case "review.snapshot":
            self = .snapshot(try BridgeProductReviewSnapshotEvent(from: decoder))
        case "review.window":
            self = .window(try BridgeProductReviewWindowEvent(from: decoder))
        case "review.delta":
            self = .delta(try BridgeProductReviewDeltaEvent(from: decoder))
        case "review.invalidated":
            self = .invalidated(try BridgeProductReviewInvalidatedEvent(from: decoder))
        case "review.reset":
            self = .reset(try BridgeProductReviewResetEvent(from: decoder))
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Unknown Review metadata event",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .sourceAccepted(let event): try event.encode(to: encoder)
        case .snapshot(let event): try event.encode(to: encoder)
        case .window(let event): try event.encode(to: encoder)
        case .delta(let event): try event.encode(to: encoder)
        case .invalidated(let event): try event.encode(to: encoder)
        case .reset(let event): try event.encode(to: encoder)
        }
    }
}

private func rejectReviewLifecycleEventUnknownKeys(
    from decoder: Decoder,
    additionalKeys: Set<String>,
    contract: String
) throws {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: BridgeProductReviewMetadataIdentity.codingKeyNames.union(additionalKeys),
        contract: contract
    )
}
