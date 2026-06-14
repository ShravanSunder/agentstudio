import Foundation

struct BridgeReviewPipelineRequest: Codable, Equatable, Sendable {
    let packageId: String
    let query: BridgeReviewQuery
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let checkpointIds: [String]
    let reviewGeneration: BridgeReviewGeneration
    let generatedAtUnixMilliseconds: Int64
}
