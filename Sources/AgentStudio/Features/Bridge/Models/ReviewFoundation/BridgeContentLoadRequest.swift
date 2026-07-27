import Foundation

package struct BridgeContentLoadRequest: Codable, Equatable, Sendable {
    let handle: BridgeContentHandle
    let requestedGeneration: BridgeReviewGeneration
}

package struct BridgeContentStreamRequest: Equatable, Sendable {
    let handle: BridgeContentHandle
    let requestedGeneration: BridgeReviewGeneration
}
