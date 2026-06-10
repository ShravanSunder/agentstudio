import Foundation

struct BridgeEndpointComparison: Codable, Equatable, Sendable {
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let changedFiles: [BridgeEndpointChangedFile]
}

struct BridgeEndpointChangedFile: Codable, Equatable, Sendable {
    let fileId: String
    let path: String
    let oldPath: String?
    let changeKind: BridgeFileChangeKind
    let language: String?
    let fileExtension: String?
    let sizeBytes: Int
    let oldContentHash: String?
    let newContentHash: String?
    let contentHashAlgorithm: String
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let mimeType: String
}
