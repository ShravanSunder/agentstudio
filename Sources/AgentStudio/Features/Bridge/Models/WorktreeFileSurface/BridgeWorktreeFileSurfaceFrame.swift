import Foundation

struct BridgeWorktreeFileSurfaceSourceIdentity: Codable, Equatable, Sendable {
    let sourceId: String
    let repoId: String
    let worktreeId: String
    let subscriptionGeneration: Int
    let sourceCursor: String
    let rootRevisionToken: String?
}

enum BridgeWorktreeFileSurfaceFreshness: String, Codable, Equatable, Sendable {
    case live
}

struct BridgeWorktreeFileSurfaceSourceSpec: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clientRequestId
        case repoId
        case worktreeId
        case rootPathToken
        case cwdScope
        case pathScope
        case includeStatuses
        case includeComments
        case includeAgentComms
        case freshness
    }

    private struct SourceSpecAnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    let clientRequestId: String
    let repoId: UUID
    let worktreeId: UUID
    let rootPathToken: String
    let cwdScope: String?
    let pathScope: [String]
    let includeStatuses: Bool
    let includeComments: Bool
    let includeAgentComms: Bool
    let freshness: BridgeWorktreeFileSurfaceFreshness

    init(
        clientRequestId: String,
        repoId: UUID,
        worktreeId: UUID,
        rootPathToken: String,
        cwdScope: String?,
        pathScope: [String],
        includeStatuses: Bool,
        includeComments: Bool,
        includeAgentComms: Bool,
        freshness: BridgeWorktreeFileSurfaceFreshness
    ) {
        self.clientRequestId = clientRequestId
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.rootPathToken = rootPathToken
        self.cwdScope = cwdScope
        self.pathScope = pathScope
        self.includeStatuses = includeStatuses
        self.includeComments = includeComments
        self.includeAgentComms = includeAgentComms
        self.freshness = freshness
    }

    init(from decoder: Decoder) throws {
        let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        let rawContainer = try decoder.container(keyedBy: SourceSpecAnyCodingKey.self)
        for key in rawContainer.allKeys where !allowedKeys.contains(key.stringValue) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: rawContainer,
                debugDescription: "Unexpected Worktree/File source-spec key"
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.clientRequestId = try Self.decodeNonBlankString(
            from: container,
            forKey: .clientRequestId
        )
        self.repoId = try container.decode(UUID.self, forKey: .repoId)
        self.worktreeId = try container.decode(UUID.self, forKey: .worktreeId)
        self.rootPathToken = try Self.decodeNonBlankString(
            from: container,
            forKey: .rootPathToken
        )
        self.cwdScope =
            if container.contains(.cwdScope) {
                try Self.decodeNonBlankString(from: container, forKey: .cwdScope)
            } else {
                nil
            }
        self.pathScope =
            if container.contains(.pathScope) {
                try Self.decodeNonBlankStringArray(from: container, forKey: .pathScope)
            } else {
                []
            }
        self.includeStatuses =
            if container.contains(.includeStatuses) {
                try container.decode(Bool.self, forKey: .includeStatuses)
            } else {
                true
            }
        self.includeComments =
            if container.contains(.includeComments) {
                try container.decode(Bool.self, forKey: .includeComments)
            } else {
                false
            }
        self.includeAgentComms =
            if container.contains(.includeAgentComms) {
                try container.decode(Bool.self, forKey: .includeAgentComms)
            } else {
                false
            }
        self.freshness = try container.decode(BridgeWorktreeFileSurfaceFreshness.self, forKey: .freshness)
    }

    private static func decodeNonBlankString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        let value = try container.decode(String.self, forKey: key)
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Worktree/File source-spec string must be non-empty"
            )
        }
        return value
    }

    private static func decodeNonBlankStringArray(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [String] {
        let values = try container.decode([String].self, forKey: key)
        for value in values where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Worktree/File source-spec path scope entries must be non-empty"
            )
        }
        return values
    }
}

enum BridgeDemandLane: String, Codable, Equatable, Sendable {
    case foreground
    case active
    case visible
    case nearby
    case speculative
    case idle
}

struct BridgeWorktreeTreeRowMetadata: Codable, Equatable, Sendable {
    let rowId: String
    let path: String
    let name: String
    let parentPath: String?
    let depth: Int
    let isDirectory: Bool
    let fileId: String?
    let sizeBytes: Int?
    let lineCount: Int?
    let changeStatus: String?

    enum CodingKeys: String, CodingKey {
        case rowId
        case path
        case name
        case parentPath
        case depth
        case isDirectory
        case fileId
        case sizeBytes
        case lineCount
        case changeStatus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rowId, forKey: .rowId)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        if let parentPath {
            try container.encode(parentPath, forKey: .parentPath)
        } else {
            try container.encodeNil(forKey: .parentPath)
        }
        try container.encode(depth, forKey: .depth)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encodeIfPresent(fileId, forKey: .fileId)
        try container.encodeIfPresent(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(lineCount, forKey: .lineCount)
        try container.encodeIfPresent(changeStatus, forKey: .changeStatus)
    }
}
