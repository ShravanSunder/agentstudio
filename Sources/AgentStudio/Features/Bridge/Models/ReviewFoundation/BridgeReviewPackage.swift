import Foundation

struct BridgeReviewPackage: Codable, Equatable, Sendable {
    let packageId: String
    let schemaVersion: Int
    let reviewGeneration: BridgeReviewGeneration
    let revision: Int
    let query: BridgeReviewQuery
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let orderedItemIds: [String]
    let itemsById: [String: BridgeReviewItemDescriptor]
    let groups: [BridgeReviewGroup]
    let summary: BridgeReviewPackageSummary
    let filterState: BridgeViewFilter
    let generatedAtUnixMilliseconds: Int64
    let changesetCluster: BridgeReviewChangesetClusterMetadata?

    init(
        packageId: String,
        schemaVersion: Int,
        reviewGeneration: BridgeReviewGeneration,
        revision: Int,
        query: BridgeReviewQuery,
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        orderedItemIds: [String],
        itemsById: [String: BridgeReviewItemDescriptor],
        groups: [BridgeReviewGroup],
        summary: BridgeReviewPackageSummary,
        filterState: BridgeViewFilter,
        generatedAtUnixMilliseconds: Int64,
        changesetCluster: BridgeReviewChangesetClusterMetadata? = nil
    ) {
        self.packageId = packageId
        self.schemaVersion = schemaVersion
        self.reviewGeneration = reviewGeneration
        self.revision = revision
        self.query = query
        self.baseEndpoint = baseEndpoint
        self.headEndpoint = headEndpoint
        self.orderedItemIds = orderedItemIds
        self.itemsById = itemsById
        self.groups = groups
        self.summary = summary
        self.filterState = filterState
        self.generatedAtUnixMilliseconds = generatedAtUnixMilliseconds
        self.changesetCluster = changesetCluster
    }
}

struct BridgeReviewPackageSummary: Codable, Equatable, Sendable {
    let filesChanged: Int
    let additions: Int
    let deletions: Int
    let visibleFileCount: Int
    let hiddenFileCount: Int
}

struct BridgeReviewGroup: Codable, Equatable, Sendable {
    let groupId: String
    let grouping: BridgeChangeGrouping
    let label: String
    let orderedItemIds: [String]
    let summary: BridgeReviewGroupSummary
    let hiddenSummary: BridgeHiddenSummary
}

struct BridgeReviewGroupSummary: Codable, Equatable, Sendable {
    let filesChanged: Int
    let additions: Int
    let deletions: Int
}

struct BridgeHiddenSummary: Codable, Equatable, Sendable {
    let hiddenFileCount: Int
    let hiddenAdditions: Int
    let hiddenDeletions: Int
    let hiddenFileClasses: [BridgeFileClass]
}
