import Foundation

struct BridgeReviewItemDescriptorRequest: Codable, Equatable, Sendable {
    let endpoint: BridgeSourceEndpoint
    let path: String
    let reviewGeneration: BridgeReviewGeneration
}
