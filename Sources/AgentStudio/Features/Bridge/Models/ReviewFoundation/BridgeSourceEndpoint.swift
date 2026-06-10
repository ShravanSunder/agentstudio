import Foundation

struct BridgeSourceEndpoint: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case gitRef
        case workingTree
        case index
        case promptCheckpoint
        case sessionCheckpoint
        case manualCheckpoint
        case savedTimeWindowCheckpoint
    }

    let endpointId: String
    let kind: Kind
    let repoId: UUID
    let worktreeId: UUID
    let label: String
    let createdAtUnixMilliseconds: Int64
    let contentSetHash: String?
    let providerIdentity: String
}
