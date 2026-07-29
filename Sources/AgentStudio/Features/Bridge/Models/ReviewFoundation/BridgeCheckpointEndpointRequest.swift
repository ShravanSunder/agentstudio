import Foundation

package struct BridgeCheckpointEndpointRequest: Codable, Equatable, Sendable {
    let checkpointId: String
    let reviewGeneration: BridgeReviewGeneration
}
