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

        try BridgeProductContractDecoding.validateUUID(repoId, codingPath: decoder.codingPath)
        if let rootRevisionToken {
            try BridgeProductContractDecoding.validateOpaqueReference(
                rootRevisionToken,
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateOpaqueReference(sourceCursor, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(sourceId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            subscriptionGeneration,
            name: "subscriptionGeneration",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateUUID(worktreeId, codingPath: decoder.codingPath)
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

struct BridgeProductReviewMetadataEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case generation
        case packageId
        case revision
        case sourceIdentity
    }

    let generation: Int
    let packageId: String
    let revision: Int
    let sourceIdentity: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review metadata event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "review.sourceAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid review metadata event kind",
                codingPath: decoder.codingPath
            )
        }
        self.generation = try container.decode(Int.self, forKey: .generation)
        self.packageId = try container.decode(String.self, forKey: .packageId)
        self.revision = try container.decode(Int.self, forKey: .revision)
        self.sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        try BridgeProductContractDecoding.validateNonnegative(
            generation,
            name: "generation",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            revision,
            name: "revision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review.sourceAccepted", forKey: .eventKind)
        try container.encode(generation, forKey: .generation)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(revision, forKey: .revision)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
    }
}

struct BridgeProductFileMetadataEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case source
    }

    let source: BridgeProductFileSourceIdentity

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file metadata event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.sourceAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid file metadata event kind",
                codingPath: decoder.codingPath
            )
        }
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.sourceAccepted", forKey: .eventKind)
        try container.encode(source, forKey: .source)
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
