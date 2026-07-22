import Foundation

struct BridgeContentLoadResult: Codable, Equatable, Sendable {
    let handle: BridgeContentHandle
    let data: Data
    let mimeType: String
    let contentHash: String
    let contentHashAlgorithm: String
}

typealias BridgeContentStreamEmitter = @Sendable (Data) async throws -> Void

struct BridgeContentStreamResult: Equatable, Sendable {
    let handle: BridgeContentHandle
    let byteCount: Int
    let mimeType: String
    let contentHash: String
    let contentHashAlgorithm: String
}
