import Foundation

enum BridgeReadyMethod: RPCMethod {
    struct Params: Decodable {}
    typealias Result = RPCNoResponse

    static let method = "bridge.ready"
}

enum BridgeIntakeReadyMethod: RPCMethod {
    struct Params: Decodable {
        let protocolId: String
        let streamId: String?
        let generation: Int?
        let reason: String?

        init(protocolId: String, streamId: String?, generation: Int? = nil, reason: String? = nil) {
            self.protocolId = protocolId
            self.streamId = streamId
            self.generation = generation
            self.reason = reason
        }
    }
    typealias Result = RPCNoResponse

    static let method = "bridge.intakeReady"
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

enum BridgeActiveViewerModeUpdateMethod: RPCMethod {
    struct Params: Decodable, Equatable, Sendable {
        let sessionId: String
        let sequence: Int
        let mode: BridgeActiveViewerMode
        let activeSource: BridgeActiveViewerSource?
    }
    typealias Result = RPCNoResponse

    static let method = "bridge.activeViewerMode.update"
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
    case intakeReannounce = "intake_reannounce"
    case suppressionCatchUp = "suppression_catch_up"
    case filesystemRefresh = "filesystem_refresh"
    case fallbackUnresolvedHead = "fallback_unresolved_head"
}

struct BridgeSuppressedProtocolDrop: Equatable, Sendable {
    let generation: Int
    let nextSequenceAtDrop: Int
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

struct BridgeMethodUnimplementedError: Error, LocalizedError, Sendable {
    let method: String

    var errorDescription: String? {
        "Unimplemented bridge method: \(method)"
    }
}
