import Foundation

struct BridgeReviewCheckpoint: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case prompt
        case session
        case manual
        case savedTimeWindow
    }

    let checkpointId: String
    let checkpointKind: Kind
    let repoId: UUID
    let worktreeId: UUID
    let paneId: UUID
    let createdAtUnixMilliseconds: Int64
    let reviewGeneration: BridgeReviewGeneration
    let baseEndpointId: String
    let headEndpointId: String
    let eventSequenceStart: UInt64
    let eventSequenceEnd: UInt64
    let batchSequenceStart: UInt64
    let batchSequenceEnd: UInt64
    let contentSetHash: String
    let agentSessionId: String?
    let promptId: String?
    let summary: String
}
