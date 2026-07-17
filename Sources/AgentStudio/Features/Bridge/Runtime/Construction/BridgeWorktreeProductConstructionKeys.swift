import Foundation

struct BridgeWorktreeIdentityKey: Hashable, Sendable {
    let repoIdentity: String
    let worktreeIdentity: String
    let stableRootIdentity: String
}

struct BridgeWorktreeProductOwnerKey: Hashable, Sendable {
    let worktree: BridgeWorktreeIdentityKey
    let providerIdentity: String

    init(
        repoIdentity: String,
        worktreeIdentity: String,
        stableRootIdentity: String,
        providerIdentity: String
    ) {
        worktree = BridgeWorktreeIdentityKey(
            repoIdentity: repoIdentity,
            worktreeIdentity: worktreeIdentity,
            stableRootIdentity: stableRootIdentity
        )
        self.providerIdentity = providerIdentity
    }
}

struct BridgeFileStatusSemanticsKey: Hashable, Sendable {
    let includesUntracked: Bool
    let includesIgnored: Bool
    let detectsRenames: Bool
    let recursesUntrackedDirectories: Bool
}

struct BridgeFileIgnoreSemanticsKey: Hashable, Sendable {
    let respectsRepositoryIgnore: Bool
    let respectsInfoExclude: Bool
    let respectsGlobalIgnore: Bool
    let additionalPatternIdentity: String?
}

struct BridgeFileConstructionKey: Hashable, Sendable {
    let owner: BridgeWorktreeProductOwnerKey
    let canonicalWorkingDirectoryIdentity: String
    let pathScope: [String]
    let statusSemantics: BridgeFileStatusSemanticsKey
    let ignoreSemantics: BridgeFileIgnoreSemanticsKey

    init(
        owner: BridgeWorktreeProductOwnerKey,
        canonicalWorkingDirectoryIdentity: String,
        pathScope: [String],
        statusSemantics: BridgeFileStatusSemanticsKey,
        ignoreSemantics: BridgeFileIgnoreSemanticsKey
    ) {
        self.owner = owner
        self.canonicalWorkingDirectoryIdentity = canonicalWorkingDirectoryIdentity
        self.pathScope = Self.canonicalSet(pathScope)
        self.statusSemantics = statusSemantics
        self.ignoreSemantics = ignoreSemantics
    }

    private static func canonicalSet(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

enum BridgeReviewQueryKindKey: String, Hashable, Sendable {
    case compare
    case openFile
    case browseTree
    case filterPackage
    case groupPackage
}

enum BridgeReviewComparisonSemanticsKey: String, Hashable, Sendable {
    case twoDot
    case threeDot
    case checkpointDelta
    case indexDelta
    case workingTreeDelta
    case notApplicable
}

enum BridgeResolvedReviewEndpointKindKey: String, Hashable, Sendable {
    case gitObject
    case workingTree
    case index
    case checkpoint
}

struct BridgeResolvedReviewEndpointKey: Hashable, Sendable {
    let kind: BridgeResolvedReviewEndpointKindKey
    let providerIdentity: String
    let contentIdentity: String
}

struct BridgeReviewViewFilterKey: Hashable, Sendable {
    let includedPathGlobs: [String]
    let excludedPathGlobs: [String]
    let includedFileClasses: [String]
    let excludedFileClasses: [String]
    let includedExtensions: [String]
    let excludedExtensions: [String]
    let changeKinds: [String]
    let reviewStates: [String]
    let showsHiddenFiles: Bool
    let showsBinaryFiles: Bool
    let showsLargeFiles: Bool

    init(
        includedPathGlobs: [String],
        excludedPathGlobs: [String],
        includedFileClasses: [String],
        excludedFileClasses: [String],
        includedExtensions: [String],
        excludedExtensions: [String],
        changeKinds: [String],
        reviewStates: [String],
        showsHiddenFiles: Bool,
        showsBinaryFiles: Bool,
        showsLargeFiles: Bool
    ) {
        self.includedPathGlobs = Self.canonicalSet(includedPathGlobs)
        self.excludedPathGlobs = Self.canonicalSet(excludedPathGlobs)
        self.includedFileClasses = Self.canonicalSet(includedFileClasses)
        self.excludedFileClasses = Self.canonicalSet(excludedFileClasses)
        self.includedExtensions = Self.canonicalSet(includedExtensions)
        self.excludedExtensions = Self.canonicalSet(excludedExtensions)
        self.changeKinds = Self.canonicalSet(changeKinds)
        self.reviewStates = Self.canonicalSet(reviewStates)
        self.showsHiddenFiles = showsHiddenFiles
        self.showsBinaryFiles = showsBinaryFiles
        self.showsLargeFiles = showsLargeFiles
    }

    private static func canonicalSet(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

enum BridgeReviewGroupingKindKey: String, Hashable, Sendable {
    case flat
    case folder
    case fileClass
    case changeKind
    case reviewState
    case agentStream
    case prompt
    case session
    case checkpoint
    case timeWindow
    case custom
}

struct BridgeReviewGroupingKey: Hashable, Sendable {
    let kind: BridgeReviewGroupingKindKey
    let label: String?
}

struct BridgeReviewProvenanceFilterKey: Hashable, Sendable {
    let paneIdentities: [UUID]
    let agentSessionIdentities: [String]
    let promptIdentities: [String]
    let operationIdentities: [String]
    let createdAfterUnixMilliseconds: Int64?
    let createdBeforeUnixMilliseconds: Int64?
    let sourceKinds: [String]

    init(
        paneIdentities: [UUID],
        agentSessionIdentities: [String],
        promptIdentities: [String],
        operationIdentities: [String],
        createdAfterUnixMilliseconds: Int64?,
        createdBeforeUnixMilliseconds: Int64?,
        sourceKinds: [String]
    ) {
        self.paneIdentities = Array(Set(paneIdentities)).sorted { $0.uuidString < $1.uuidString }
        self.agentSessionIdentities = Self.canonicalSet(agentSessionIdentities)
        self.promptIdentities = Self.canonicalSet(promptIdentities)
        self.operationIdentities = Self.canonicalSet(operationIdentities)
        self.createdAfterUnixMilliseconds = createdAfterUnixMilliseconds
        self.createdBeforeUnixMilliseconds = createdBeforeUnixMilliseconds
        self.sourceKinds = Self.canonicalSet(sourceKinds)
    }

    private static func canonicalSet(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

enum BridgeReviewCheckpointKindKey: String, Hashable, Sendable {
    case prompt
    case session
    case manual
    case savedTimeWindow
}

struct BridgeReviewCheckpointSemanticsKey: Hashable, Sendable {
    let kind: BridgeReviewCheckpointKindKey
    let contentIdentity: String
    let eventSequenceBounds: ClosedRange<UInt64>
    let batchSequenceBounds: ClosedRange<UInt64>
}

struct BridgeReviewConstructionKey: Hashable, Sendable {
    let owner: BridgeWorktreeProductOwnerKey
    let queryKind: BridgeReviewQueryKindKey
    let comparisonSemantics: BridgeReviewComparisonSemanticsKey
    let canonicalWorkingDirectoryIdentity: String
    let baseEndpoint: BridgeResolvedReviewEndpointKey
    let headEndpoint: BridgeResolvedReviewEndpointKey
    let pathScope: [String]
    let fileTarget: String?
    let viewFilter: BridgeReviewViewFilterKey
    let grouping: BridgeReviewGroupingKey
    let provenance: BridgeReviewProvenanceFilterKey
    let checkpoint: BridgeReviewCheckpointSemanticsKey?

    init(
        owner: BridgeWorktreeProductOwnerKey,
        queryKind: BridgeReviewQueryKindKey,
        comparisonSemantics: BridgeReviewComparisonSemanticsKey,
        canonicalWorkingDirectoryIdentity: String,
        baseEndpoint: BridgeResolvedReviewEndpointKey,
        headEndpoint: BridgeResolvedReviewEndpointKey,
        pathScope: [String],
        fileTarget: String?,
        viewFilter: BridgeReviewViewFilterKey,
        grouping: BridgeReviewGroupingKey,
        provenance: BridgeReviewProvenanceFilterKey,
        checkpoint: BridgeReviewCheckpointSemanticsKey?
    ) {
        self.owner = owner
        self.queryKind = queryKind
        self.comparisonSemantics = comparisonSemantics
        self.canonicalWorkingDirectoryIdentity = canonicalWorkingDirectoryIdentity
        self.baseEndpoint = baseEndpoint
        self.headEndpoint = headEndpoint
        self.pathScope = Array(Set(pathScope)).sorted()
        self.fileTarget = fileTarget
        self.viewFilter = viewFilter
        self.grouping = grouping
        self.provenance = provenance
        self.checkpoint = checkpoint
    }
}

enum BridgeWorktreeProductConstructionKey: Hashable, Sendable {
    case file(BridgeFileConstructionKey)
    case review(BridgeReviewConstructionKey)

    var owner: BridgeWorktreeProductOwnerKey {
        switch self {
        case .file(let key):
            return key.owner
        case .review(let key):
            return key.owner
        }
    }

    var productKind: BridgeWorktreeProductKind {
        switch self {
        case .file:
            return .file
        case .review:
            return .review
        }
    }

    var worktree: BridgeWorktreeIdentityKey {
        owner.worktree
    }
}
