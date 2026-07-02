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

struct BridgeWorktreeFileSurfaceOpenSourceOutcome: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case protocolId = "protocol"
        case streamId
        case generation
    }

    private struct OutcomeAnyCodingKey: CodingKey {
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

    let status: String
    let protocolId: String
    let streamId: String
    let generation: Int

    init(streamId: String, generation: Int) {
        self.status = "accepted"
        self.protocolId = "worktree-file"
        self.streamId = streamId
        self.generation = generation
    }

    init(from decoder: Decoder) throws {
        let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        let rawContainer = try decoder.container(keyedBy: OutcomeAnyCodingKey.self)
        for key in rawContainer.allKeys where !allowedKeys.contains(key.stringValue) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: rawContainer,
                debugDescription: "Unexpected Worktree/File open-source outcome key"
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = try container.decode(String.self, forKey: .status)
        guard decodedStatus == "accepted" else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Worktree/File open-source outcome status must be accepted"
            )
        }
        let decodedProtocolId = try container.decode(String.self, forKey: .protocolId)
        guard decodedProtocolId == "worktree-file" else {
            throw DecodingError.dataCorruptedError(
                forKey: .protocolId,
                in: container,
                debugDescription: "Worktree/File open-source outcome protocol must be worktree-file"
            )
        }
        let decodedStreamId = try container.decode(String.self, forKey: .streamId)
        guard decodedStreamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DecodingError.dataCorruptedError(
                forKey: .streamId,
                in: container,
                debugDescription: "Worktree/File open-source outcome streamId must be non-empty"
            )
        }
        let decodedGeneration = try container.decode(Int.self, forKey: .generation)
        guard decodedGeneration >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .generation,
                in: container,
                debugDescription: "Worktree/File open-source outcome generation must be nonnegative"
            )
        }
        self.status = decodedStatus
        self.protocolId = decodedProtocolId
        self.streamId = decodedStreamId
        self.generation = decodedGeneration
    }
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

enum BridgeWorktreeTreeVirtualizedExtentKind: String, Codable, Equatable, Sendable {
    case exactPathCount
    case estimatedTotalHeight
}

struct BridgeWorktreeTreeVirtualizedSizeFacts: Codable, Equatable, Sendable {
    let extentKind: BridgeWorktreeTreeVirtualizedExtentKind
    let pathCount: Int?
    let windowStartIndex: Int?
    let windowRowCount: Int?
    let rowHeightPixels: Double
    let estimatedTotalHeightPixels: Double?
}

struct BridgeWorktreeTreeProjectionIdentity: Codable, Equatable, Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let pathScope: [String]
    let sortKey: String?
    let groupKey: String?
    let filterKey: String?
    let treeWindowKey: String?
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

enum BridgeDemandLane: String, Codable, Equatable, Sendable {
    case foreground
    case active
    case visible
    case nearby
    case speculative
    case idle
}

struct BridgeWorktreeFileDescriptorRequest: Codable, Equatable, Sendable {
    let sourceIdentity: BridgeWorktreeFileSurfaceSourceIdentity
    let rowId: String
    let path: String
    let fileId: String
    let lane: BridgeDemandLane
}

enum BridgeWorktreeFileVirtualizedExtentKind: String, Codable, Equatable, Sendable {
    case exactLineCount
    case estimatedHeight
    case previewBounded
    case unavailable
}

enum BridgeWorktreeFileInvalidationReason: String, Codable, Equatable, Sendable {
    case filesystemEvent
    case gitStatusChanged
    case contentChanged
    case sourceReset
    case unknown
}

enum BridgeWorktreeResetReason: String, Codable, Equatable, Sendable {
    case sourceChanged
    case subscriptionReset
    case providerRestart
    case authorityChanged
}

enum BridgeWorktreeExtentDiagnosticsRejectionReason: String, Codable, Equatable, Sendable {
    case selectorEscapesRoot
    case rootTokenMismatch
    case unsupportedComments
    case unsupportedAgentComms
    case unreadableContent
    case oversizedContent
}

/// Typed frame-level demand lineage (spec: performance-demand-lanes.md,
/// one-lineage-per-frame). Rows never carry duplicated per-row lineage.
struct BridgeWorktreeFileMetadataLineage: Codable, Equatable, Sendable {
    let loadedBy: String
    let lane: String
}

struct BridgeWorktreeSnapshotFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let requestSelector: BridgeWorktreeFileSurfaceSourceSpec?
    let treeRows: [BridgeWorktreeTreeRowMetadata]
    let treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts
    let statusPatch: BridgeWorktreeStatusPatch?
    let metadataLineage: BridgeWorktreeFileMetadataLineage

    init(
        streamId: String,
        sequence: Int,
        source: BridgeWorktreeFileSurfaceSourceIdentity,
        requestSelector: BridgeWorktreeFileSurfaceSourceSpec?,
        treeRows: [BridgeWorktreeTreeRowMetadata],
        treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts,
        statusPatch: BridgeWorktreeStatusPatch?,
        metadataLineage: BridgeWorktreeFileMetadataLineage
    ) {
        self.kind = "snapshot"
        self.streamId = streamId
        self.generation = source.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.snapshot"
        self.source = source
        self.requestSelector = requestSelector
        self.treeRows = treeRows
        self.treeSizeFacts = treeSizeFacts
        self.statusPatch = statusPatch
        self.metadataLineage = metadataLineage
    }
}

struct BridgeWorktreeTreeWindowFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let projectionIdentity: BridgeWorktreeTreeProjectionIdentity
    let rows: [BridgeWorktreeTreeRowMetadata]
    let treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts
    let metadataLineage: BridgeWorktreeFileMetadataLineage

    init(
        streamId: String,
        sequence: Int,
        projectionIdentity: BridgeWorktreeTreeProjectionIdentity,
        rows: [BridgeWorktreeTreeRowMetadata],
        treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts,
        metadataLineage: BridgeWorktreeFileMetadataLineage
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = projectionIdentity.source.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.treeWindow"
        self.projectionIdentity = projectionIdentity
        self.rows = rows
        self.treeSizeFacts = treeSizeFacts
        self.metadataLineage = metadataLineage
    }
}

enum BridgeWorktreeTreeOperation: Codable, Equatable, Sendable {
    case upsertRows([BridgeWorktreeTreeRowMetadata])
    case removeRows(rowIds: [String], paths: [String]?)

    private enum CodingKeys: String, CodingKey {
        case op
        case rows
        case rowIds
        case paths
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsertRows(let rows):
            try container.encode("upsertRows", forKey: .op)
            try container.encode(rows, forKey: .rows)
        case .removeRows(let rowIds, let paths):
            try container.encode("removeRows", forKey: .op)
            try container.encode(rowIds, forKey: .rowIds)
            try container.encodeIfPresent(paths, forKey: .paths)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try container.decode(String.self, forKey: .op)
        switch operation {
        case "upsertRows":
            self = .upsertRows(
                try container.decode([BridgeWorktreeTreeRowMetadata].self, forKey: .rows)
            )
        case "removeRows":
            self = .removeRows(
                rowIds: try container.decode([String].self, forKey: .rowIds),
                paths: try container.decodeIfPresent([String].self, forKey: .paths)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .op,
                in: container,
                debugDescription: "unknown worktree tree operation: \(operation)"
            )
        }
    }
}

struct BridgeWorktreeTreeDeltaFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let operations: [BridgeWorktreeTreeOperation]

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        operations: [BridgeWorktreeTreeOperation]
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "worktree.treeDelta"
        self.operations = operations
    }
}

struct BridgeWorktreeFileDescriptor: Codable, Equatable, Sendable {
    let path: String
    let fileId: String
    let contentHandle: String
    let contentDescriptor: BridgeAttachedResourceDescriptor
    let contentHash: String?
    let sourceIdentity: BridgeWorktreeFileSurfaceSourceIdentity
    let sizeBytes: Int
    let virtualizedExtentKind: BridgeWorktreeFileVirtualizedExtentKind
    let lineCount: Int?
    let estimatedContentHeightPixels: Double?
    let isBinary: Bool
    let language: String?
    let fileExtension: String?
    let modifiedAtUnixMilliseconds: Int?
}

struct BridgeWorktreeFileDescriptorFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let descriptor: BridgeWorktreeFileDescriptor

    init(
        streamId: String,
        sequence: Int,
        descriptor: BridgeWorktreeFileDescriptor
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = descriptor.sourceIdentity.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.fileDescriptor"
        self.descriptor = descriptor
    }
}

struct BridgeWorktreeFileInvalidation: Codable, Equatable, Sendable {
    let path: String
    let fileId: String?
    let reason: BridgeWorktreeFileInvalidationReason
    let contentHandleIds: [String]?
    let latestDescriptor: BridgeWorktreeFileDescriptor?
}

struct BridgeWorktreeFileInvalidatedFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let invalidation: BridgeWorktreeFileInvalidation

    init(
        streamId: String,
        sequence: Int,
        source: BridgeWorktreeFileSurfaceSourceIdentity,
        invalidation: BridgeWorktreeFileInvalidation
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = source.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.fileInvalidated"
        self.source = source
        self.invalidation = invalidation
    }
}

struct BridgeWorktreeStatusPatchCounts: Codable, Equatable, Sendable {
    let staged: Int?
    let unstaged: Int?
    let untracked: Int?
}

struct BridgeWorktreeStatusPatchBranchFacts: Codable, Equatable, Sendable {
    let branchName: String?
    let ahead: Int?
    let behind: Int?
}

struct BridgeWorktreeStatusPatch: Codable, Equatable, Sendable {
    let path: String?
    let status: String?
    let staged: Int?
    let unstaged: Int?
    let untracked: Int?
    let branchName: String?
    let ahead: Int?
    let behind: Int?

    init(
        path: String? = nil,
        status: String? = nil,
        counts: BridgeWorktreeStatusPatchCounts,
        branchFacts: BridgeWorktreeStatusPatchBranchFacts
    ) {
        self.path = path
        self.status = status
        self.staged = counts.staged
        self.unstaged = counts.unstaged
        self.untracked = counts.untracked
        self.branchName = branchFacts.branchName
        self.ahead = branchFacts.ahead
        self.behind = branchFacts.behind
    }
}

struct BridgeWorktreeStatusPatchFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let patch: BridgeWorktreeStatusPatch

    init(
        streamId: String,
        sequence: Int,
        source: BridgeWorktreeFileSurfaceSourceIdentity,
        patch: BridgeWorktreeStatusPatch
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = source.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.statusPatch"
        self.source = source
        self.patch = patch
    }
}

struct BridgeWorktreeResetFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let reason: BridgeWorktreeResetReason
    let source: BridgeWorktreeFileSurfaceSourceIdentity?
    let replacementDescriptor: BridgeAttachedResourceDescriptor?

    init(
        streamId: String,
        sequence: Int,
        reason: BridgeWorktreeResetReason,
        source: BridgeWorktreeFileSurfaceSourceIdentity?,
        replacementDescriptor: BridgeAttachedResourceDescriptor?
    ) {
        self.kind = "reset"
        self.streamId = streamId
        self.generation = source?.subscriptionGeneration ?? 0
        self.sequence = sequence
        self.frameKind = "worktree.reset"
        self.reason = reason
        self.source = source
        self.replacementDescriptor = replacementDescriptor
    }
}

struct BridgeWorktreeExtentDiagnostics: Codable, Equatable, Sendable {
    let sourceId: String
    let subscriptionGeneration: Int
    let totalTreePathCount: Int
    let treeEstimatedTotalHeightPixels: Double?
    let fileExtentKindCounts: [BridgeWorktreeFileVirtualizedExtentKind: Int]
    let rejectionReasonCounts: [BridgeWorktreeExtentDiagnosticsRejectionReason: Int]
}
