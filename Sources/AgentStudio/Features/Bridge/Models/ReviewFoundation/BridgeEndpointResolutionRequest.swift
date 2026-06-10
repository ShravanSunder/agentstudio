import Foundation

struct BridgeEndpointResolutionRequest: Codable, Equatable, Sendable {
    let endpoint: BridgeSourceEndpoint
}
