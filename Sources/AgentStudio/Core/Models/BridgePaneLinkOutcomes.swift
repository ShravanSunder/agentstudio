import Foundation

package enum BridgeMemberAdditionEffect: String, Codable, Hashable, Sendable {
    case newItem
    case newContribution
}

package enum BridgeDraftKeptReason: String, Codable, Hashable, Sendable {
    case refused
    case saveFailed
    case saveOutcomeUnknown
}

/// All outcome JSON is a flat tagged object. The decoder checks the exact
/// fields for each case before any associated value is interpreted.
struct BridgeOutcomeWire: Encodable {
    let kind: String
    var effect: BridgeMemberAdditionEffect?
    var operationId: UUID?
    var removedContributions: [BridgeLinkContributor]?
    var reason: BridgeDraftKeptReason?

    init(
        _ kind: String,
        effect: BridgeMemberAdditionEffect? = nil,
        operationId: UUID? = nil,
        removedContributions: [BridgeLinkContributor]? = nil,
        reason: BridgeDraftKeptReason? = nil
    ) {
        self.kind = kind
        self.effect = effect
        self.operationId = operationId
        self.removedContributions = removedContributions
        self.reason = reason
    }

    static func decode(_ decoder: Decoder, fieldsByKind: [String: Set<String>]) throws -> Self {
        let container = try BridgeContractWire.decode(decoder, fieldsByKind: fieldsByKind)
        return Self(
            try container.decode(String.self, forKey: .kind),
            effect: try container.decodeIfPresent(BridgeMemberAdditionEffect.self, forKey: .effect),
            operationId: try container.decodeIfPresent(UUID.self, forKey: .operationId),
            removedContributions: try container.decodeIfPresent(
                [BridgeLinkContributor].self, forKey: .removedContributions
            ),
            reason: try container.decodeIfPresent(BridgeDraftKeptReason.self, forKey: .reason)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(effect, forKey: .effect)
        try container.encodeIfPresent(operationId, forKey: .operationId)
        try container.encodeIfPresent(removedContributions, forKey: .removedContributions)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

package enum BridgeMemberAddResult: Hashable, Sendable, Codable {
    case added(effect: BridgeMemberAdditionEffect)
    case alreadyPresent
    case refusedUnknownWorktree
    case staleOwner
    case staleReceiver
    case unsupportedReceiver

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "added": ["effect"], "alreadyPresent": [], "refusedUnknownWorktree": [],
                "staleOwner": [], "staleReceiver": [], "unsupportedReceiver": [],
            ])
        switch wire.kind {
        case "added": self = .added(effect: try BridgeOutcomeWire.require(wire.effect, decoder))
        case "alreadyPresent": self = .alreadyPresent
        case "refusedUnknownWorktree": self = .refusedUnknownWorktree
        case "staleOwner": self = .staleOwner
        case "staleReceiver": self = .staleReceiver
        case "unsupportedReceiver": self = .unsupportedReceiver
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try wire.encode(to: encoder) }

    private var wire: BridgeOutcomeWire {
        switch self {
        case .added(let effect): BridgeOutcomeWire("added", effect: effect)
        case .alreadyPresent: BridgeOutcomeWire("alreadyPresent")
        case .refusedUnknownWorktree: BridgeOutcomeWire("refusedUnknownWorktree")
        case .staleOwner: BridgeOutcomeWire("staleOwner")
        case .staleReceiver: BridgeOutcomeWire("staleReceiver")
        case .unsupportedReceiver: BridgeOutcomeWire("unsupportedReceiver")
        }
    }
}

package enum BridgeMemberRemoveResult: Hashable, Sendable, Codable {
    case removed(removedContributions: [BridgeLinkContributor])
    case alreadyAbsent
    case refusedProtectedCurrentDirectory
    case refusedNotAuthor
    case staleOwner
    case staleReceiver
    case pendingDraftSettlement(operationId: UUID)

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "removed": ["removedContributions"], "alreadyAbsent": [],
                "refusedProtectedCurrentDirectory": [], "refusedNotAuthor": [],
                "staleOwner": [], "staleReceiver": [], "pendingDraftSettlement": ["operationId"],
            ])
        switch wire.kind {
        case "removed":
            self = .removed(
                removedContributions: try BridgeOutcomeWire.require(
                    wire.removedContributions, decoder
                ))
        case "alreadyAbsent": self = .alreadyAbsent
        case "refusedProtectedCurrentDirectory": self = .refusedProtectedCurrentDirectory
        case "refusedNotAuthor": self = .refusedNotAuthor
        case "staleOwner": self = .staleOwner
        case "staleReceiver": self = .staleReceiver
        case "pendingDraftSettlement":
            self = .pendingDraftSettlement(
                operationId: try BridgeOutcomeWire.require(
                    wire.operationId, decoder
                ))
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try wire.encode(to: encoder) }

    private var wire: BridgeOutcomeWire {
        switch self {
        case .removed(let contributions): BridgeOutcomeWire("removed", removedContributions: contributions)
        case .alreadyAbsent: BridgeOutcomeWire("alreadyAbsent")
        case .refusedProtectedCurrentDirectory: BridgeOutcomeWire("refusedProtectedCurrentDirectory")
        case .refusedNotAuthor: BridgeOutcomeWire("refusedNotAuthor")
        case .staleOwner: BridgeOutcomeWire("staleOwner")
        case .staleReceiver: BridgeOutcomeWire("staleReceiver")
        case .pendingDraftSettlement(let operationId):
            BridgeOutcomeWire(
                "pendingDraftSettlement", operationId: operationId
            )
        }
    }
}

package enum BridgePendingMemberRemovalSettlement: Hashable, Sendable, Codable {
    case removed(removedContributions: [BridgeLinkContributor])
    case alreadyAbsent
    case refusedProtectedCurrentDirectory
    case refusedNotAuthor
    case staleOwner
    case staleReceiver
    case draftKept(reason: BridgeDraftKeptReason)
    case membershipOutcomeUnknown

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "removed": ["removedContributions"], "alreadyAbsent": [],
                "refusedProtectedCurrentDirectory": [], "refusedNotAuthor": [],
                "staleOwner": [], "staleReceiver": [], "draftKept": ["reason"],
                "membershipOutcomeUnknown": [],
            ])
        switch wire.kind {
        case "removed":
            self = .removed(
                removedContributions: try BridgeOutcomeWire.require(
                    wire.removedContributions, decoder
                ))
        case "alreadyAbsent": self = .alreadyAbsent
        case "refusedProtectedCurrentDirectory": self = .refusedProtectedCurrentDirectory
        case "refusedNotAuthor": self = .refusedNotAuthor
        case "staleOwner": self = .staleOwner
        case "staleReceiver": self = .staleReceiver
        case "draftKept": self = .draftKept(reason: try BridgeOutcomeWire.require(wire.reason, decoder))
        case "membershipOutcomeUnknown": self = .membershipOutcomeUnknown
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try wire.encode(to: encoder) }

    private var wire: BridgeOutcomeWire {
        switch self {
        case .removed(let contributions): BridgeOutcomeWire("removed", removedContributions: contributions)
        case .alreadyAbsent: BridgeOutcomeWire("alreadyAbsent")
        case .refusedProtectedCurrentDirectory: BridgeOutcomeWire("refusedProtectedCurrentDirectory")
        case .refusedNotAuthor: BridgeOutcomeWire("refusedNotAuthor")
        case .staleOwner: BridgeOutcomeWire("staleOwner")
        case .staleReceiver: BridgeOutcomeWire("staleReceiver")
        case .draftKept(let reason): BridgeOutcomeWire("draftKept", reason: reason)
        case .membershipOutcomeUnknown: BridgeOutcomeWire("membershipOutcomeUnknown")
        }
    }
}

package enum BridgePullRequestReferenceAddResult: Hashable, Sendable, Codable {
    case added(effect: BridgeMemberAdditionEffect)
    case alreadyPresent
    case staleOwner
    case staleReceiver
    case unsupportedReceiver

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "added": ["effect"], "alreadyPresent": [], "staleOwner": [],
                "staleReceiver": [], "unsupportedReceiver": [],
            ])
        switch wire.kind {
        case "added": self = .added(effect: try BridgeOutcomeWire.require(wire.effect, decoder))
        case "alreadyPresent": self = .alreadyPresent
        case "staleOwner": self = .staleOwner
        case "staleReceiver": self = .staleReceiver
        case "unsupportedReceiver": self = .unsupportedReceiver
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try wire.encode(to: encoder) }

    private var wire: BridgeOutcomeWire {
        switch self {
        case .added(let effect): BridgeOutcomeWire("added", effect: effect)
        case .alreadyPresent: BridgeOutcomeWire("alreadyPresent")
        case .staleOwner: BridgeOutcomeWire("staleOwner")
        case .staleReceiver: BridgeOutcomeWire("staleReceiver")
        case .unsupportedReceiver: BridgeOutcomeWire("unsupportedReceiver")
        }
    }
}

package enum BridgePullRequestReferenceRemoveResult: Hashable, Sendable, Codable {
    case removed(removedContributions: [BridgeLinkContributor])
    case alreadyAbsent
    case refusedNotAuthor
    case staleOwner
    case staleReceiver

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "removed": ["removedContributions"], "alreadyAbsent": [],
                "refusedNotAuthor": [], "staleOwner": [], "staleReceiver": [],
            ])
        switch wire.kind {
        case "removed":
            self = .removed(
                removedContributions: try BridgeOutcomeWire.require(
                    wire.removedContributions, decoder
                ))
        case "alreadyAbsent": self = .alreadyAbsent
        case "refusedNotAuthor": self = .refusedNotAuthor
        case "staleOwner": self = .staleOwner
        case "staleReceiver": self = .staleReceiver
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try wire.encode(to: encoder) }

    private var wire: BridgeOutcomeWire {
        switch self {
        case .removed(let contributions): BridgeOutcomeWire("removed", removedContributions: contributions)
        case .alreadyAbsent: BridgeOutcomeWire("alreadyAbsent")
        case .refusedNotAuthor: BridgeOutcomeWire("refusedNotAuthor")
        case .staleOwner: BridgeOutcomeWire("staleOwner")
        case .staleReceiver: BridgeOutcomeWire("staleReceiver")
        }
    }
}

extension BridgeOutcomeWire {
    static func require<Value>(_ value: Value?, _ decoder: Decoder) throws -> Value {
        guard let value else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing associated outcome value"
                ))
        }
        return value
    }
}
