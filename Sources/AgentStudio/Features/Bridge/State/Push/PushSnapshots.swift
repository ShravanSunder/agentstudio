import Foundation

/// Wire payload for diff status push.
/// Pushed to React on `.hot` level — immediate user feedback for loading states.
struct DiffStatusSlice: Encodable, Equatable, Sendable {
    let status: DiffStatus
    let error: String?
    let epoch: Int
}

/// Wire payload for connection health push.
/// Pushed on `.hot` level — connection changes need immediate UI response.
struct ConnectionSlice: Encodable, Equatable, Sendable {
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

    init(
        commandId: String,
        status: Status,
        reason: String?,
        method: String,
        canonicalId: String?
    ) {
        self.commandId = commandId
        self.status = status
        self.method = method
        self.canonicalId = canonicalId

        switch status {
        case .ok:
            self.reason = nil
        case .rejected:
            let normalized = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.reason = (normalized?.isEmpty == false) ? normalized : "Command rejected"
        }
    }
}
