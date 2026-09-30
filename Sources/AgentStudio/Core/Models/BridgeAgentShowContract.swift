import Foundation

/// A validated local file request in a known worktree. The optional line is one-based.
package struct BridgeAgentShowTarget: Hashable, Sendable, Codable {
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
            decoder, required: ["worktree", "relativePath"], optional: ["line"])
        try self.init(
            worktree: container.decode(WorktreeId.self, forKey: .worktree),
            relativePath: container.decode(String.self, forKey: .relativePath),
            line: container.decodeIfPresent(Int.self, forKey: .line))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        try container.encode(worktree, forKey: .worktree)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(line, forKey: .line)
    }
}

/// IPC request choice. Background is the default; IPC obtains human approval
/// before invoking the native take-over method.
package enum BridgeAgentShowMode: String, CaseIterable, Hashable, Sendable, Codable {
    /// Add the file to Open files and post a best-effort pane notification.
    case background
    /// After approval, add the file and request ordinary human activation.
    case takeOver

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(decoder, fieldsByKind: fieldsByKind(Self.allCases))
        let kind = try container.decode(String.self, forKey: .kind)
        guard let mode = Self(rawValue: kind) else { throw BridgeContractWire.invalidKind(decoder) }
        self = mode
    }

    package func encode(to encoder: Encoder) throws { try BridgeOutcomeWire(rawValue).encode(to: encoder) }
}

/// Native result of adding a prepared file to the receiver's Open files.
package enum BridgeAgentBackgroundOpenResult: String, CaseIterable, Hashable, Sendable, Codable {
    /// The inventory applied the file; notification delivery is best-effort.
    case opened
    /// The target is unknown, missing, non-local, or outside its worktree.
    case notFound
    /// The receiver is gone or retired; no effect was applied.
    case paneUnavailable

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(decoder, fieldsByKind: fieldsByKind(Self.allCases))
        let kind = try container.decode(String.self, forKey: .kind)
        guard let result = Self(rawValue: kind) else { throw BridgeContractWire.invalidKind(decoder) }
        self = result
    }

    package func encode(to encoder: Encoder) throws { try BridgeOutcomeWire(rawValue).encode(to: encoder) }
}

/// Native result of an already-approved take-over request.
package enum BridgeAgentTakeOverResult: String, CaseIterable, Hashable, Sendable, Codable {
    /// Human activation reported the file displayed.
    case shown
    /// The file opened, but a draft or newer navigation kept it off screen.
    case opened
    /// The target is unknown, missing, non-local, or outside its worktree.
    case notFound
    /// The receiver is gone or retired; no effect was applied.
    case paneUnavailable

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(decoder, fieldsByKind: fieldsByKind(Self.allCases))
        let kind = try container.decode(String.self, forKey: .kind)
        guard let result = Self(rawValue: kind) else { throw BridgeContractWire.invalidKind(decoder) }
        self = result
    }

    package func encode(to encoder: Encoder) throws { try BridgeOutcomeWire(rawValue).encode(to: encoder) }
}

/// IPC-facing answer. Only the IPC permission gate can produce declined.
package enum BridgeAgentShowReply: String, CaseIterable, Hashable, Sendable, Codable {
    /// The file is in Open files, without confirmed display.
    case opened
    /// Human activation reported the file displayed.
    case shown
    /// The person refused IPC take-over approval; the file remains open in background.
    case declined
    /// The target is unknown, missing, non-local, or outside its worktree.
    case notFound
    /// The receiver is gone or retired; no effect was applied.
    case paneUnavailable

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(decoder, fieldsByKind: fieldsByKind(Self.allCases))
        let kind = try container.decode(String.self, forKey: .kind)
        guard let reply = Self(rawValue: kind) else { throw BridgeContractWire.invalidKind(decoder) }
        self = reply
    }

    package func encode(to encoder: Encoder) throws { try BridgeOutcomeWire(rawValue).encode(to: encoder) }
}

private func fieldsByKind<Case: RawRepresentable>(_ cases: [Case]) -> [String: Set<String>]
where Case.RawValue == String {
    Dictionary(uniqueKeysWithValues: cases.map { ($0.rawValue, Set<String>()) })
}

/// Pure mapping at the IPC gate from a native background result to its reply.
package func bridgeAgentShowReply(for result: BridgeAgentBackgroundOpenResult) -> BridgeAgentShowReply {
    switch result {
    case .opened: .opened
    case .notFound: .notFound
    case .paneUnavailable: .paneUnavailable
    }
}

/// Pure mapping at the IPC gate from an already-approved take-over result.
package func bridgeAgentShowReply(for result: BridgeAgentTakeOverResult) -> BridgeAgentShowReply {
    switch result {
    case .shown: .shown
    case .opened: .opened
    case .notFound: .notFound
    case .paneUnavailable: .paneUnavailable
    }
}
