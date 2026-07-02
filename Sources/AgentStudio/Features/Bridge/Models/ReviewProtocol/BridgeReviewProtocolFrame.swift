import Foundation

struct BridgeReviewChangesetClusterMetadata: Codable, Equatable, Sendable {
    let clusterId: String
    let sourceId: String
    let algorithm: String
    let lifecycle: String
    let confidence: String
    let baselineCursor: String?
    let headCursor: String?
    let baselineRef: String?
    let headRef: String?
    let fromUnixMilliseconds: Int?
    let toUnixMilliseconds: Int?
    let includedPathHints: [String]?
    let groupingReason: String?
    let limitations: [String]?
}

struct BridgeReviewComparisonIdentity: Codable, Equatable, Sendable {
    let packageId: String
    let sourceIdentity: String
    let generation: Int
    let revision: Int
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let contentDescriptors: [BridgeAttachedResourceDescriptor]
    let changesetCluster: BridgeReviewChangesetClusterMetadata?
}

enum BridgeReviewMetadataLoadedBy: String, Codable, Equatable, Sendable {
    case startupWindow = "startup_window"
    case foreground
    case visible
    case nearby
    case speculative
    case idle
    case delta
    case reset
    case replacement
}

struct BridgeReviewTreeRowMetadata: Encodable, Equatable, Sendable {
    let rowId: String
    let itemId: String?
    let path: String
    let depth: Int
    let isDirectory: Bool
    let loadedBy: BridgeReviewMetadataLoadedBy
    let lane: BridgeDemandLane

    private enum CodingKeys: String, CodingKey {
        case rowId
        case itemId
        case path
        case depth
        case isDirectory
        case loadedBy = "loaded_by"
        case lane
    }
}

struct BridgeReviewExtentFact: Encodable, Equatable, Sendable {
    let itemId: String
    let contentRole: String
    let lineCount: Int
}

struct BridgeReviewProjectionItemProvenance: Encodable, Equatable, Sendable {
    let promptIds: [String]
    let agentSessionIds: [String]
    let operationIds: [String]
}

struct BridgeReviewProjectionContentDescriptorIdsByRole: Encodable, Equatable, Sendable {
    let base: String?
    let head: String?
    let diff: String?
    let file: String?
}

struct BridgeReviewProjectionInputItem: Encodable, Equatable, Sendable {
    let itemId: String
    let basePath: String?
    let headPath: String?
    let changeKind: String
    let fileClass: String
    let language: String?
    let `extension`: String?
    let isHiddenByDefault: Bool
    let reviewPriority: String
    let reviewState: String
    let contentRoles: [String]
    let contentDescriptorIdsByRole: BridgeReviewProjectionContentDescriptorIdsByRole?
    let mimeTypes: [String]
    let provenance: BridgeReviewProjectionItemProvenance
    let loadedBy: BridgeReviewMetadataLoadedBy
    let lane: BridgeDemandLane

    private enum CodingKeys: String, CodingKey {
        case itemId
        case basePath
        case headPath
        case changeKind
        case fileClass
        case language
        case `extension`
        case isHiddenByDefault
        case reviewPriority
        case reviewState
        case contentRoles
        case contentDescriptorIdsByRole
        case mimeTypes
        case provenance
        case loadedBy = "loaded_by"
        case lane
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(basePath, forKey: .basePath)
        try container.encode(headPath, forKey: .headPath)
        try container.encode(changeKind, forKey: .changeKind)
        try container.encode(fileClass, forKey: .fileClass)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(`extension`, forKey: .extension)
        try container.encode(isHiddenByDefault, forKey: .isHiddenByDefault)
        try container.encode(reviewPriority, forKey: .reviewPriority)
        try container.encode(reviewState, forKey: .reviewState)
        try container.encode(contentRoles, forKey: .contentRoles)
        try container.encodeIfPresent(contentDescriptorIdsByRole, forKey: .contentDescriptorIdsByRole)
        try container.encode(mimeTypes, forKey: .mimeTypes)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(loadedBy, forKey: .loadedBy)
        try container.encode(lane, forKey: .lane)
    }
}

enum BridgeReviewMetadataOperation: Encodable, Equatable, Sendable {
    case upsertItemMetadata(BridgeReviewProjectionInputItem)
    case removeItems([String])
    case appendItems([BridgeReviewProjectionInputItem])
    case replaceItemOrder([String])
    case upsertTreeRows([BridgeReviewTreeRowMetadata])
    case removeTreeRows(rowIds: [String]?, paths: [String]?)
    case replaceTreeWindow([BridgeReviewTreeRowMetadata])
    case movePathPrefix(fromPath: String, toPath: String, affectedItemIds: [String])
    case upsertExtentFacts([BridgeReviewExtentFact])
    case selectItem(String?)
    case invalidateContentDescriptors([String])

    private enum CodingKeys: String, CodingKey {
        case kind
        case item
        case itemIds
        case items
        case rows
        case rowIds
        case paths
        case fromPath
        case toPath
        case affectedItemIds
        case facts
        case itemId
        case descriptorIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsertItemMetadata(let item):
            try container.encode("upsertItemMetadata", forKey: .kind)
            try container.encode(item, forKey: .item)
        case .removeItems(let itemIds):
            try container.encode("removeItems", forKey: .kind)
            try container.encode(itemIds, forKey: .itemIds)
        case .appendItems(let items):
            try container.encode("appendItems", forKey: .kind)
            try container.encode(items, forKey: .items)
        case .replaceItemOrder(let itemIds):
            try container.encode("replaceItemOrder", forKey: .kind)
            try container.encode(itemIds, forKey: .itemIds)
        case .upsertTreeRows(let rows):
            try container.encode("upsertTreeRows", forKey: .kind)
            try container.encode(rows, forKey: .rows)
        case .removeTreeRows(let rowIds, let paths):
            try container.encode("removeTreeRows", forKey: .kind)
            try container.encodeIfPresent(rowIds, forKey: .rowIds)
            try container.encodeIfPresent(paths, forKey: .paths)
        case .replaceTreeWindow(let rows):
            try container.encode("replaceTreeWindow", forKey: .kind)
            try container.encode(rows, forKey: .rows)
        case .movePathPrefix(let fromPath, let toPath, let affectedItemIds):
            try container.encode("movePathPrefix", forKey: .kind)
            try container.encode(fromPath, forKey: .fromPath)
            try container.encode(toPath, forKey: .toPath)
            try container.encode(affectedItemIds, forKey: .affectedItemIds)
        case .upsertExtentFacts(let facts):
            try container.encode("upsertExtentFacts", forKey: .kind)
            try container.encode(facts, forKey: .facts)
        case .selectItem(let itemId):
            try container.encode("selectItem", forKey: .kind)
            try container.encode(itemId, forKey: .itemId)
        case .invalidateContentDescriptors(let descriptorIds):
            try container.encode("invalidateContentDescriptors", forKey: .kind)
            try container.encode(descriptorIds, forKey: .descriptorIds)
        }
    }
}

struct BridgeReviewSnapshotFrame: Encodable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let comparison: BridgeReviewComparisonIdentity
    let selectedItemId: String?
    let visibleItemIds: [String]
    let itemMetadata: [BridgeReviewProjectionInputItem]
    let treeRows: [BridgeReviewTreeRowMetadata]
    let extentFacts: [BridgeReviewExtentFact]
    let summary: BridgeReviewPackageSummary

    private enum CodingKeys: String, CodingKey {
        case kind
        case streamId
        case generation
        case sequence
        case frameKind
        case comparison
        case selectedItemId
        case visibleItemIds
        case itemMetadata
        case treeRows
        case extentFacts
        case summary
    }

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        comparison: BridgeReviewComparisonIdentity,
        selectedItemId: String?,
        visibleItemIds: [String],
        itemMetadata: [BridgeReviewProjectionInputItem],
        treeRows: [BridgeReviewTreeRowMetadata],
        extentFacts: [BridgeReviewExtentFact],
        summary: BridgeReviewPackageSummary
    ) {
        self.kind = "metadataSnapshot"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.metadataSnapshot"
        self.comparison = comparison
        self.selectedItemId = selectedItemId
        self.visibleItemIds = visibleItemIds
        self.itemMetadata = itemMetadata
        self.treeRows = treeRows
        self.extentFacts = extentFacts
        self.summary = summary
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(streamId, forKey: .streamId)
        try container.encode(generation, forKey: .generation)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(frameKind, forKey: .frameKind)
        try container.encode(comparison, forKey: .comparison)
        try container.encode(selectedItemId, forKey: .selectedItemId)
        try container.encode(visibleItemIds, forKey: .visibleItemIds)
        try container.encode(itemMetadata, forKey: .itemMetadata)
        try container.encode(treeRows, forKey: .treeRows)
        try container.encode(extentFacts, forKey: .extentFacts)
        try container.encode(summary, forKey: .summary)
    }
}

struct BridgeReviewMetadataWindowFrame: Encodable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let packageId: String
    let revision: Int
    let itemMetadata: [BridgeReviewProjectionInputItem]
    let treeRows: [BridgeReviewTreeRowMetadata]
    let extentFacts: [BridgeReviewExtentFact]
    let summary: BridgeReviewPackageSummary
    let contentDescriptors: [BridgeAttachedResourceDescriptor]

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        packageId: String,
        revision: Int,
        itemMetadata: [BridgeReviewProjectionInputItem],
        treeRows: [BridgeReviewTreeRowMetadata],
        extentFacts: [BridgeReviewExtentFact],
        summary: BridgeReviewPackageSummary,
        contentDescriptors: [BridgeAttachedResourceDescriptor]
    ) {
        self.kind = "metadataWindow"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.metadataWindow"
        self.packageId = packageId
        self.revision = revision
        self.itemMetadata = itemMetadata
        self.treeRows = treeRows
        self.extentFacts = extentFacts
        self.summary = summary
        self.contentDescriptors = contentDescriptors
    }
}

struct BridgeReviewDeltaFrame: Encodable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let packageId: String
    let fromRevision: Int
    let toRevision: Int
    let operations: [BridgeReviewMetadataOperation]
    let summary: BridgeReviewPackageSummary
    let contentDescriptors: [BridgeAttachedResourceDescriptor]

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        packageId: String,
        fromRevision: Int,
        toRevision: Int,
        operations: [BridgeReviewMetadataOperation],
        summary: BridgeReviewPackageSummary,
        contentDescriptors: [BridgeAttachedResourceDescriptor]
    ) {
        self.kind = "metadataDelta"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.metadataDelta"
        self.packageId = packageId
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.operations = operations
        self.summary = summary
        self.contentDescriptors = contentDescriptors
    }
}

struct BridgeReviewInvalidationFrame: Encodable, Equatable, Sendable {
    struct Invalidation: Encodable, Equatable, Sendable {
        let scope: String
        let itemIds: [String]?
        let pathHints: [String]?
        let reason: String
    }

    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let invalidation: Invalidation

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        invalidation: Invalidation
    ) {
        self.kind = "delta"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.invalidate"
        self.invalidation = invalidation
    }
}

struct BridgeReviewResetFrame: Encodable, Equatable, Sendable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let frameKind: String
    let reason: String
    let sourceIdentity: String

    init(
        streamId: String,
        generation: Int,
        sequence: Int,
        reason: String,
        sourceIdentity: String
    ) {
        self.kind = "reset"
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.frameKind = "review.reset"
        self.reason = reason
        self.sourceIdentity = sourceIdentity
    }
}

enum BridgeReviewProtocolFrame: Encodable, Equatable, Sendable {
    case snapshot(BridgeReviewSnapshotFrame)
    case metadataWindow(BridgeReviewMetadataWindowFrame)
    case delta(BridgeReviewDeltaFrame)
    case invalidation(BridgeReviewInvalidationFrame)
    case reset(BridgeReviewResetFrame)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .snapshot(let frame):
            try frame.encode(to: encoder)
        case .metadataWindow(let frame):
            try frame.encode(to: encoder)
        case .delta(let frame):
            try frame.encode(to: encoder)
        case .invalidation(let frame):
            try frame.encode(to: encoder)
        case .reset(let frame):
            try frame.encode(to: encoder)
        }
    }
}
