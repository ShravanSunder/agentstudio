import Foundation

struct BridgeContentLoadResult: Codable, Equatable, Sendable {
    let handle: BridgeContentHandle
    let data: Data
    let mimeType: String
    let contentHash: String
    let contentHashAlgorithm: String
}
