import Foundation

package struct BridgeContentLoadResult: Codable, Equatable, Sendable {
    let handle: BridgeContentHandle
    let data: Data
    let mimeType: String
    let contentHash: String
    let contentHashAlgorithm: String
}

package typealias BridgeContentStreamEmitter = @Sendable (Data) async throws -> Void

package struct BridgeContentStreamResult: Equatable, Sendable {
    let handle: BridgeContentHandle
    let byteCount: Int
    let mimeType: String
    let contentHash: String
    let contentHashAlgorithm: String
}
