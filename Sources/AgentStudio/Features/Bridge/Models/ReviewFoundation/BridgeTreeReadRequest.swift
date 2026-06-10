import Foundation

struct BridgeTreeReadRequest: Codable, Equatable, Sendable {
    let endpoint: BridgeSourceEndpoint
    let pathScope: [String]
    let reviewGeneration: BridgeReviewGeneration
}

struct BridgeTreeReadResult: Codable, Equatable, Sendable {
    let endpoint: BridgeSourceEndpoint
    let descriptors: [BridgeReviewItemDescriptor]
}
