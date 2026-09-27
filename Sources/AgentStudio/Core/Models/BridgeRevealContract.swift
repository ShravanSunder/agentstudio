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

/// The caller chooses whether the file stays in Open files or requests human
/// approval to take over the visible pane. Background is the default at IPC.
package enum BridgeAgentShowMode: String, Hashable, Sendable, Codable {
    case background
    case takeOver

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(
            decoder, fieldsByKind: ["background": [], "takeOver": []]
        )
        let kind = try container.decode(String.self, forKey: .kind)
        guard let mode = Self(rawValue: kind) else { throw BridgeContractWire.invalidKind(decoder) }
        self = mode
    }

    package func encode(to encoder: Encoder) throws {
        try BridgeOutcomeWire(rawValue).encode(to: encoder)
    }
}

/// Exactly one answer to one show request. A declined take-over leaves the
/// already-opened file in the receiver's background inventory.
package enum BridgeAgentShowResult: String, Hashable, Sendable, Codable {
    case opened
    case shown
    case declined
    case notFound
    case paneUnavailable

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(
            decoder,
            fieldsByKind: [
                "opened": [], "shown": [], "declined": [], "notFound": [], "paneUnavailable": [],
            ])
        let kind = try container.decode(String.self, forKey: .kind)
        guard let result = Self(rawValue: kind) else { throw BridgeContractWire.invalidKind(decoder) }
        self = result
    }

    package func encode(to encoder: Encoder) throws {
        try BridgeOutcomeWire(rawValue).encode(to: encoder)
    }
}
