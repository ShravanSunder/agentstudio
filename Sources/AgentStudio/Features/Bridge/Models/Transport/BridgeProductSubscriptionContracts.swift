import Foundation

enum BridgeProductDemandLane: String, Codable, Equatable, Sendable {
    case foreground
    case active
    case visible
    case nearby
    case speculative
    case idle
}

enum BridgeProductSubscriptionKind: String, Codable, Equatable, Sendable {
    case fileMetadata = "file.metadata"
    case reviewMetadata = "review.metadata"

    var surface: BridgeProductSurface {
        switch self {
        case .fileMetadata: .file
        case .reviewMetadata: .review
        }
    }
}

struct BridgeProductFileSourceSpec: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cwdScope
        case freshness
        case includeStatuses
        case repoId
        case rootPathToken
        case worktreeId
    }

    let cwdScope: String?
    let includeStatuses: Bool
    let repoId: String
    let rootPathToken: String
    let worktreeId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file source spec"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cwdScope = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .cwdScope,
            from: container,
            codingPath: decoder.codingPath
        )
        guard try container.decode(String.self, forKey: .freshness) == "live" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product file source freshness must be live",
                codingPath: decoder.codingPath
            )
        }
        self.includeStatuses = try container.decode(Bool.self, forKey: .includeStatuses)
        self.repoId = try container.decode(String.self, forKey: .repoId)
        self.rootPathToken = try container.decode(String.self, forKey: .rootPathToken)
        self.worktreeId = try container.decode(String.self, forKey: .worktreeId)

        if let cwdScope {
            try BridgeProductContractDecoding.validateDisplayPath(cwdScope, codingPath: decoder.codingPath)
        }
        try BridgeProductContractDecoding.validateUUID(repoId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateOpaqueReference(rootPathToken, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateUUID(worktreeId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cwdScope, forKey: .cwdScope)
        try container.encode("live", forKey: .freshness)
        try container.encode(includeStatuses, forKey: .includeStatuses)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(rootPathToken, forKey: .rootPathToken)
        try container.encode(worktreeId, forKey: .worktreeId)
    }
}

enum BridgeProductSubscriptionRequest: Codable, Equatable, Sendable {
    case fileMetadata(BridgeProductFileSourceSpec)
    case reviewMetadata

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source
        case subscriptionKind
    }

    var subscriptionKind: BridgeProductSubscriptionKind {
        switch self {
        case .fileMetadata: .fileMetadata
        case .reviewMetadata: .reviewMetadata
        }
    }

    var surface: BridgeProductSurface { subscriptionKind.surface }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product subscription request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind) {
        case .fileMetadata:
            self = .fileMetadata(
                try container.decode(BridgeProductFileSourceSpec.self, forKey: .source)
            )
        case .reviewMetadata:
            guard !container.contains(.source) else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review metadata subscription cannot carry file source configuration",
                    codingPath: decoder.codingPath
                )
            }
            self = .reviewMetadata
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
        switch self {
        case .fileMetadata(let source):
            try container.encode(source, forKey: .source)
        case .reviewMetadata:
            break
        }
    }
}

struct BridgeProductFileSourceIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case repoId
        case rootRevisionToken
        case sourceCursor
        case sourceId
        case subscriptionGeneration
        case worktreeId
    }

    let repoId: String
    let rootRevisionToken: String?
    let sourceCursor: String
    let sourceId: String
    let subscriptionGeneration: Int
    let worktreeId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file source identity"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.repoId = try container.decode(String.self, forKey: .repoId)
        self.rootRevisionToken = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .rootRevisionToken,
            from: container,
            codingPath: decoder.codingPath
        )
        self.sourceCursor = try container.decode(String.self, forKey: .sourceCursor)
        self.sourceId = try container.decode(String.self, forKey: .sourceId)
        self.subscriptionGeneration = try container.decode(Int.self, forKey: .subscriptionGeneration)
        self.worktreeId = try container.decode(String.self, forKey: .worktreeId)

        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateUUID(repoId, codingPath: codingPath)
        if let rootRevisionToken {
            try BridgeProductContractDecoding.validateOpaqueReference(
                rootRevisionToken,
                codingPath: codingPath
            )
        }
        try BridgeProductContractDecoding.validateOpaqueReference(sourceCursor, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(sourceId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            subscriptionGeneration,
            name: "subscriptionGeneration",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateUUID(worktreeId, codingPath: codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(rootRevisionToken, forKey: .rootRevisionToken)
        try container.encode(sourceCursor, forKey: .sourceCursor)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(subscriptionGeneration, forKey: .subscriptionGeneration)
        try container.encode(worktreeId, forKey: .worktreeId)
    }
}

enum BridgeProductSubscriptionData: Codable, Equatable, Sendable {
    case fileMetadata(BridgeProductFileMetadataEvent)
    case reviewMetadata(BridgeProductReviewMetadataEvent)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case event
        case subscriptionKind
    }

    var subscriptionKind: BridgeProductSubscriptionKind {
        switch self {
        case .fileMetadata: .fileMetadata
        case .reviewMetadata: .reviewMetadata
        }
    }

    var surface: BridgeProductSurface { subscriptionKind.surface }

    var sourceGeneration: Int {
        switch self {
        case .fileMetadata(let event): event.sourceGeneration
        case .reviewMetadata(let event): event.generation
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product subscription data"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind) {
        case .fileMetadata:
            self = .fileMetadata(
                try container.decode(BridgeProductFileMetadataEvent.self, forKey: .event)
            )
        case .reviewMetadata:
            self = .reviewMetadata(
                try container.decode(BridgeProductReviewMetadataEvent.self, forKey: .event)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
        switch self {
        case .fileMetadata(let event):
            try container.encode(event, forKey: .event)
        case .reviewMetadata(let event):
            try container.encode(event, forKey: .event)
        }
    }
}
