import Foundation

struct BridgeEndpointComparisonRequest: Codable, Equatable, Sendable {
    let query: BridgeReviewQuery
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let reviewGeneration: BridgeReviewGeneration
}
