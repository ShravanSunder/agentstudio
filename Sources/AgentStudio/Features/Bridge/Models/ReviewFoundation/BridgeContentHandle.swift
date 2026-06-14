import Foundation

struct BridgeContentHandle: Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Hashable, Sendable {
        case base
        case head
        case diff
        case file
    }

    let handleId: String
    let itemId: String
    let role: Role
    let endpointId: String
    let reviewGeneration: BridgeReviewGeneration
    let resourceUrl: String
    let contentHash: String
    let contentHashAlgorithm: String
    let cacheKey: String
    let mimeType: String
    let language: String?
    let sizeBytes: Int
    let isBinary: Bool
}
