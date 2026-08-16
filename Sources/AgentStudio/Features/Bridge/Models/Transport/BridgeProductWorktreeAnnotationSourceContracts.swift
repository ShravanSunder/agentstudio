import Foundation

enum BridgeProductWorktreeAnnotationAdmission: Codable, Equatable, Sendable {
    case implicitOrSingle
    case newSession
    case selected(UUID)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case sessionId
    }

    private enum Kind: String, Codable {
        case implicitOrSingle
        case newSession
        case selected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .implicitOrSingle:
            try rejectSourceContractUnknownKeys(decoder, allowed: Set<CodingKeys>([.kind]))
            self = .implicitOrSingle
        case .newSession:
            try rejectSourceContractUnknownKeys(decoder, allowed: Set<CodingKeys>([.kind]))
            self = .newSession
        case .selected:
            try rejectSourceContractUnknownKeys(decoder, allowed: Set<CodingKeys>([.kind, .sessionId]))
            self = .selected(try decodeSourceContractUUIDv7(container, forKey: .sessionId, decoder: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .implicitOrSingle:
            try container.encode(Kind.implicitOrSingle, forKey: .kind)
        case .newSession:
            try container.encode(Kind.newSession, forKey: .kind)
        case .selected(let sessionID):
            try container.encode(Kind.selected, forKey: .kind)
            try container.encode(
                BridgeProductReviewPublicationIdContract.encode(sessionID),
                forKey: .sessionId
            )
        }
    }
}

enum BridgeProductWorktreeAnnotationSourceRole: String, Codable, Equatable, Sendable {
    case file
    case reviewBase
    case reviewHead
}

enum BridgeProductWorktreeAnnotationDiffSide: String, Codable, Equatable, Sendable {
    case additions
    case deletions
}

struct BridgeProductWorktreeAnnotationOrigin: Codable, Equatable, Sendable {
    let path: String
    let startLine: Int
    let endLine: Int
    let sourceRole: BridgeProductWorktreeAnnotationSourceRole
    let diffSide: BridgeProductWorktreeAnnotationDiffSide?
    let sourceIdentity: String

    init(
        path: String,
        startLine: Int,
        endLine: Int,
        sourceRole: BridgeProductWorktreeAnnotationSourceRole,
        diffSide: BridgeProductWorktreeAnnotationDiffSide?,
        sourceIdentity: String
    ) {
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.sourceRole = sourceRole
        self.diffSide = diffSide
        self.sourceIdentity = sourceIdentity
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case diffSide
        case endLine
        case kind
        case path
        case sourceIdentity
        case sourceRole
        case startLine
    }

    private enum Kind: String, Codable {
        case located
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(Kind.self, forKey: .kind)
        try rejectSourceContractUnknownKeys(
            decoder,
            allowed: Set<CodingKeys>([
                .diffSide, .endLine, .kind, .path, .sourceIdentity, .sourceRole, .startLine,
            ])
        )
        let path = try container.decode(String.self, forKey: .path)
        let sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        let startLine = try container.decode(Int.self, forKey: .startLine)
        let endLine = try container.decode(Int.self, forKey: .endLine)
        try validateSourceContractPath(path, sourceIdentity: sourceIdentity, decoder: decoder)
        guard startLine > 0, endLine >= startLine else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation located range is invalid",
                codingPath: decoder.codingPath
            )
        }
        self.init(
            path: path,
            startLine: startLine,
            endLine: endLine,
            sourceRole: try container.decode(
                BridgeProductWorktreeAnnotationSourceRole.self,
                forKey: .sourceRole
            ),
            diffSide: try BridgeProductContractDecoding.decodeRequiredNullable(
                BridgeProductWorktreeAnnotationDiffSide.self,
                forKey: .diffSide,
                from: container,
                codingPath: decoder.codingPath
            ),
            sourceIdentity: sourceIdentity
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Kind.located, forKey: .kind)
        try container.encode(path, forKey: .path)
        try container.encode(startLine, forKey: .startLine)
        try container.encode(endLine, forKey: .endLine)
        try container.encode(sourceRole, forKey: .sourceRole)
        try container.encode(diffSide, forKey: .diffSide)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
    }

    func validate(surface: BridgeProductSurface, codingPath: [any CodingKey]) throws {
        let isValid =
            (surface == .file && sourceRole == .file && diffSide == nil)
            || (surface == .review && sourceRole == .reviewBase && diffSide == .deletions)
            || (surface == .review && sourceRole == .reviewHead && diffSide == .additions)
        guard isValid else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation source role does not match the product surface",
                codingPath: codingPath
            )
        }
    }
}

enum BridgeProductWorktreeAnnotationOutputSelection: Codable, Equatable, Sendable {
    case explicit(messageIds: [UUID])
    case allEligible(excludedMessageIds: [UUID])

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case excludedMessageIds
        case kind
        case messageIds
    }

    private enum Kind: String, Codable {
        case explicit
        case allEligible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let ids: [UUID]
        switch kind {
        case .explicit:
            try rejectSourceContractUnknownKeys(
                decoder,
                allowed: Set<CodingKeys>([.kind, .messageIds])
            )
            ids = try Self.decodeIDs(container, forKey: .messageIds, decoder: decoder)
            guard !ids.isEmpty else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Explicit annotation output selection must not be empty",
                    codingPath: decoder.codingPath
                )
            }
            self = .explicit(messageIds: ids)
        case .allEligible:
            try rejectSourceContractUnknownKeys(
                decoder,
                allowed: Set<CodingKeys>([.excludedMessageIds, .kind])
            )
            ids = try Self.decodeIDs(container, forKey: .excludedMessageIds, decoder: decoder)
            self = .allEligible(excludedMessageIds: ids)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .explicit(let messageIds):
            try container.encode(Kind.explicit, forKey: .kind)
            try container.encode(messageIds.map(BridgeProductReviewPublicationIdContract.encode), forKey: .messageIds)
        case .allEligible(let excludedMessageIds):
            try container.encode(Kind.allEligible, forKey: .kind)
            try container.encode(
                excludedMessageIds.map(BridgeProductReviewPublicationIdContract.encode),
                forKey: .excludedMessageIds
            )
        }
    }

    private static func decodeIDs(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        decoder: Decoder
    ) throws -> [UUID] {
        let encodedIDs = try container.decode([String].self, forKey: key)
        guard encodedIDs.count <= 64 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output selection exceeds its maximum count",
                codingPath: decoder.codingPath
            )
        }
        let ids = try encodedIDs.map {
            try BridgeProductReviewPublicationIdContract.decode($0, codingPath: decoder.codingPath)
        }
        guard Set(ids).count == ids.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output selection contains duplicate message identities",
                codingPath: decoder.codingPath
            )
        }
        return ids
    }
}

private func rejectSourceContractUnknownKeys<TCodingKey: CodingKey & RawRepresentable>(
    _ decoder: Decoder,
    allowed: Set<TCodingKey>
) throws where TCodingKey.RawValue == String {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(allowed.map(\.rawValue)),
        contract: "worktree annotation source value"
    )
}

private func decodeSourceContractUUIDv7<TCodingKey: CodingKey>(
    _ container: KeyedDecodingContainer<TCodingKey>,
    forKey key: TCodingKey,
    decoder: Decoder
) throws -> UUID {
    try BridgeProductReviewPublicationIdContract.decode(
        container.decode(String.self, forKey: key),
        codingPath: decoder.codingPath
    )
}

private func validateSourceContractPath(
    _ path: String,
    sourceIdentity: String,
    decoder: Decoder
) throws {
    try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
    try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: decoder.codingPath)
}
