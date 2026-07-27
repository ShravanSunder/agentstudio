import Foundation

package struct BridgeTreeReadRequest: Codable, Equatable, Sendable {
    let endpoint: BridgeSourceEndpoint
    let pathScope: [String]
    let reviewGeneration: BridgeReviewGeneration
}

package struct BridgeTreeReadResult: Codable, Equatable, Sendable {
    let endpoint: BridgeSourceEndpoint
    let descriptors: [BridgeReviewItemDescriptor]
}
