import Foundation

/// Wire payload for diff status push.
/// Pushed to React on `.hot` level — immediate user feedback for loading states.
struct DiffStatusSlice: Encodable, Equatable, Sendable {
    let status: DiffStatus
    let error: String?
    let epoch: Int
}

/// Wire payload for review package metadata.
/// Content bytes stay lazy and are fetched through BridgeContentHandle URLs.
struct DiffPackageMetadataSlice: Encodable, Equatable, Sendable {
    let package: BridgeReviewPackage?
    let protocolFrame: BridgeReviewProtocolFrame?

    init(
        package: BridgeReviewPackage?,
        protocolFrame: BridgeReviewSnapshotFrame? = nil
    ) {
        self.package = package
        self.protocolFrame = protocolFrame.map(BridgeReviewProtocolFrame.snapshot)
    }

    init(
        package: BridgeReviewPackage?,
        protocolFrame: BridgeReviewProtocolFrame?
    ) {
        self.package = package
        self.protocolFrame = protocolFrame
    }
}

/// Wire payload for incremental review package deltas.
/// A nil delta is a no-op marker that clears stale pending delta state.
struct DiffPackageDeltaSlice: Encodable, Equatable, Sendable {
    let delta: BridgeReviewDelta?
    let protocolFrame: BridgeReviewProtocolFrame?

    init(
        delta: BridgeReviewDelta?,
        protocolFrame: BridgeReviewDeltaFrame? = nil
    ) {
        self.delta = delta
        self.protocolFrame = protocolFrame.map(BridgeReviewProtocolFrame.delta)
    }

    init(
        delta: BridgeReviewDelta?,
        protocolFrame: BridgeReviewProtocolFrame?
    ) {
        self.delta = delta
        self.protocolFrame = protocolFrame
    }
}

/// Wire payload for standalone review protocol events without a package delta.
struct DiffPackageProtocolFrameSlice: Encodable, Equatable, Sendable {
    let protocolFrame: BridgeReviewProtocolFrame?
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
