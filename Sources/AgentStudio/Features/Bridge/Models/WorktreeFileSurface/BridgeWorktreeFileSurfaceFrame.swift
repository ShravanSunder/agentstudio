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
        case includeFileDescriptors
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
    let includeFileDescriptors: Bool
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
        includeFileDescriptors: Bool,
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
        self.includeFileDescriptors = includeFileDescriptors
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
        self.includeFileDescriptors =
            if container.contains(.includeFileDescriptors) {
                try container.decode(Bool.self, forKey: .includeFileDescriptors)
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

struct BridgeWorktreeSnapshotFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let requestSelector: BridgeWorktreeFileSurfaceSourceSpec?
    let treeDescriptor: BridgeAttachedResourceDescriptor
    let treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts
    let statusDescriptor: BridgeAttachedResourceDescriptor?

    init(
        streamId: String,
        sequence: Int,
        source: BridgeWorktreeFileSurfaceSourceIdentity,
        requestSelector: BridgeWorktreeFileSurfaceSourceSpec?,
        treeDescriptor: BridgeAttachedResourceDescriptor,
        treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts,
        statusDescriptor: BridgeAttachedResourceDescriptor?
    ) {
        self.kind = "snapshot"
        self.streamId = streamId
        self.generation = source.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.snapshot"
        self.source = source
        self.requestSelector = requestSelector
        self.treeDescriptor = treeDescriptor
        self.treeSizeFacts = treeSizeFacts
        self.statusDescriptor = statusDescriptor
    }
}

struct BridgeWorktreeTreeWindowFrame: Codable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let projectionIdentity: BridgeWorktreeTreeProjectionIdentity
    let windowDescriptor: BridgeAttachedResourceDescriptor
    let treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts

    init(
        streamId: String,
        sequence: Int,
        projectionIdentity: BridgeWorktreeTreeProjectionIdentity,
        windowDescriptor: BridgeAttachedResourceDescriptor,
        treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = projectionIdentity.source.subscriptionGeneration
        self.sequence = sequence
        self.frameKind = "worktree.treeWindow"
        self.projectionIdentity = projectionIdentity
        self.windowDescriptor = windowDescriptor
        self.treeSizeFacts = treeSizeFacts
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
