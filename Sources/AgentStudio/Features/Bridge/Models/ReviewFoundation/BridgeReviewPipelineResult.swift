import Foundation

struct BridgeReviewPipelineResult: Codable, Equatable, Sendable {
    let package: BridgeReviewPackage
    let registeredContentHandles: [BridgeContentHandle]
}
