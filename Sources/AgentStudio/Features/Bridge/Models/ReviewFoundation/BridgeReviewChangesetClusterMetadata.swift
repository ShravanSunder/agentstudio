import Foundation

/// Source-revision metadata attached to a Review package.
///
/// This belongs to the package model and is independent of the retired native
/// Review intake-frame carrier that previously happened to declare it.
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
