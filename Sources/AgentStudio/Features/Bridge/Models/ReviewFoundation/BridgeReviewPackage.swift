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
