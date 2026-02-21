import Foundation

/// Wire payload for diff status push (section 6.8).
/// Pushed to React on `.hot` level — immediate user feedback for loading states.
struct DiffStatusSlice: Encodable, Equatable {
    let status: DiffStatus
    let error: String?
    let epoch: Int
}

/// Wire payload for connection health push (section 6.8).
/// Pushed on `.hot` level — connection changes need immediate UI response.
struct ConnectionSlice: Encodable, Equatable {
    let health: ConnectionState.ConnectionHealth
    let latencyMs: Int
}

/// Command acknowledgment envelope for JSON-RPC commands.
struct CommandAck: Encodable, Equatable, Sendable {
    enum Status: String, Codable, Equatable, Sendable {
        case ok
        case rejected
    }

    let commandId: String
    let status: Status
    let reason: String?
    let method: String
    let canonicalId: String?
}
