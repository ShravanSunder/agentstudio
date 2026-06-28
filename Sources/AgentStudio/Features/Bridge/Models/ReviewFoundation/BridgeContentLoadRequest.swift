import Foundation

struct BridgeContentLoadRequest: Codable, Equatable, Sendable {
    let handle: BridgeContentHandle
    let requestedGeneration: BridgeReviewGeneration
}

struct BridgeContentStreamRequest: Equatable, Sendable {
    let handle: BridgeContentHandle
    let requestedGeneration: BridgeReviewGeneration
}
