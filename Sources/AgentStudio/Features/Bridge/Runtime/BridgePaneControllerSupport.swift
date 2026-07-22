import Foundation

enum BridgeReadyMethod {
    static let method = "bridge.ready"
}

enum BridgeActiveViewerMode: String, Decodable, Equatable, Sendable {
    case file
    case review
}

enum BridgeActiveViewerSourceProtocol: String, Decodable, Equatable, Sendable {
    case review
    case worktreeFile = "worktree-file"
}

struct BridgeActiveViewerSource: Decodable, Equatable, Sendable {
    let protocolId: BridgeActiveViewerSourceProtocol
    let streamId: String
    let generation: Int

    private enum CodingKeys: String, CodingKey {
        case protocolId = "protocol"
        case streamId
        case generation
    }
}

struct BridgeActiveViewerModeAcceptedSignal: Equatable, Sendable {
    let mode: BridgeActiveViewerMode
    let activeSource: BridgeActiveViewerSource
    let sequenceFloor: Int
}

struct BridgeActiveViewerModeSignalState: Equatable, Sendable {
    var sessionId: String?
    var lastSequence: Int?
    var acceptedSignal: BridgeActiveViewerModeAcceptedSignal?
}

enum BridgeReviewPackageBuildReason: String, Sendable {
    case initialIntake = "initial_intake"
    case productResync = "product_resync"
    case filesystemRefresh = "filesystem_refresh"
    case fallbackUnresolvedHead = "fallback_unresolved_head"
}

enum BridgeError: Error, LocalizedError, Sendable {
    case encoding(String)

    var errorDescription: String? {
        switch self {
        case .encoding(let message):
            return message
        }
    }
}
