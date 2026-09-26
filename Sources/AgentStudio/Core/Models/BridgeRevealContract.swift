import Foundation

package struct BridgeRevealFileTarget: Hashable, Sendable, Codable {
    package let worktree: WorktreeId
    package let relativePath: String
    package let line: Int?

    package init(worktree: WorktreeId, relativePath: String, line: Int? = nil) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
            !relativePath.contains("\\"),
            !relativePath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw BridgeLinkIdentityError.invalidRelativePath }
        if let line, line < 1 { throw BridgeLinkIdentityError.invalidLine }
        self.worktree = worktree
        self.relativePath = relativePath
        self.line = line
    }

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decodeFields(
            decoder, required: ["worktree", "relativePath"], optional: ["line"]
        )
        try self.init(
            worktree: container.decode(WorktreeId.self, forKey: .worktree),
            relativePath: container.decode(String.self, forKey: .relativePath),
            line: container.decodeIfPresent(Int.self, forKey: .line)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        try container.encode(worktree, forKey: .worktree)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(line, forKey: .line)
    }
}

package enum BridgeRevealAdmissionResult: Hashable, Sendable, Codable {
    case admitted(operationId: UUID)
    case unsupportedTarget
    case staleOwner
    case staleReceiver

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "admitted": ["operationId"], "unsupportedTarget": [],
                "staleOwner": [], "staleReceiver": [],
            ])
        switch wire.kind {
        case "admitted": self = .admitted(operationId: try BridgeOutcomeWire.require(wire.operationId, decoder))
        case "unsupportedTarget": self = .unsupportedTarget
        case "staleOwner": self = .staleOwner
        case "staleReceiver": self = .staleReceiver
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try wire.encode(to: encoder) }

    private var wire: BridgeOutcomeWire {
        switch self {
        case .admitted(let operationId): BridgeOutcomeWire("admitted", operationId: operationId)
        case .unsupportedTarget: BridgeOutcomeWire("unsupportedTarget")
        case .staleOwner: BridgeOutcomeWire("staleOwner")
        case .staleReceiver: BridgeOutcomeWire("staleReceiver")
        }
    }
}

package enum BridgeAgentRevealSettlement: Hashable, Sendable, Codable {
    case shown
    case waitingInOpenView
    case superseded
    case unavailable
    case notFound
    case staleOwner
    case cancelled
    case outcomeUnknown

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "shown": [], "waitingInOpenView": [], "superseded": [], "unavailable": [],
                "notFound": [], "staleOwner": [], "cancelled": [], "outcomeUnknown": [],
            ])
        switch wire.kind {
        case "shown": self = .shown
        case "waitingInOpenView": self = .waitingInOpenView
        case "superseded": self = .superseded
        case "unavailable": self = .unavailable
        case "notFound": self = .notFound
        case "staleOwner": self = .staleOwner
        case "cancelled": self = .cancelled
        case "outcomeUnknown": self = .outcomeUnknown
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws { try BridgeOutcomeWire(kind).encode(to: encoder) }

    private var kind: String {
        switch self {
        case .shown: "shown"
        case .waitingInOpenView: "waitingInOpenView"
        case .superseded: "superseded"
        case .unavailable: "unavailable"
        case .notFound: "notFound"
        case .staleOwner: "staleOwner"
        case .cancelled: "cancelled"
        case .outcomeUnknown: "outcomeUnknown"
        }
    }
}

package enum BridgeHumanOpenSettlement: Hashable, Sendable, Codable {
    case shown
    case draftKept(reason: BridgeDraftKeptReason)
    case superseded
    case unavailable
    case outcomeUnknown

    package init(from decoder: Decoder) throws {
        let wire = try BridgeOutcomeWire.decode(
            decoder,
            fieldsByKind: [
                "shown": [], "draftKept": ["reason"], "superseded": [],
                "unavailable": [], "outcomeUnknown": [],
            ])
        switch wire.kind {
        case "shown": self = .shown
        case "draftKept": self = .draftKept(reason: try BridgeOutcomeWire.require(wire.reason, decoder))
        case "superseded": self = .superseded
        case "unavailable": self = .unavailable
        case "outcomeUnknown": self = .outcomeUnknown
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws {
        switch self {
        case .shown: try BridgeOutcomeWire("shown").encode(to: encoder)
        case .draftKept(let reason): try BridgeOutcomeWire("draftKept", reason: reason).encode(to: encoder)
        case .superseded: try BridgeOutcomeWire("superseded").encode(to: encoder)
        case .unavailable: try BridgeOutcomeWire("unavailable").encode(to: encoder)
        case .outcomeUnknown: try BridgeOutcomeWire("outcomeUnknown").encode(to: encoder)
        }
    }
}

package struct BridgeRetainedOpenViewItem: Hashable, Sendable, Codable {
    package let target: BridgeRevealFileTarget
    package let requestedBy: BridgeLinkContributor
    package let retainedAt: Date

    package init(target: BridgeRevealFileTarget, requestedBy: BridgeLinkContributor, retainedAt: Date) {
        self.target = target
        self.requestedBy = requestedBy
        self.retainedAt = retainedAt
    }

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decodeFields(
            decoder, required: ["target", "requestedBy", "retainedAt"]
        )
        self.init(
            target: try container.decode(BridgeRevealFileTarget.self, forKey: .target),
            requestedBy: try container.decode(BridgeLinkContributor.self, forKey: .requestedBy),
            retainedAt: try container.decode(Date.self, forKey: .retainedAt)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        try container.encode(target, forKey: .target)
        try container.encode(requestedBy, forKey: .requestedBy)
        try container.encode(retainedAt, forKey: .retainedAt)
    }
}
