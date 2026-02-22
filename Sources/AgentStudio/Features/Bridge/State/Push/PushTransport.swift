import Foundation

// MARK: - PushLevel

/// Cadence tier for push operations.
///
/// Each level defines a debounce duration controlling how frequently
/// the bridge pushes data to the React content world:
/// - `.hot`: immediate (no debounce) — connection health and diff status
/// - `.warm`: 12ms — review threads/viewed-files and command ack streams
/// - `.cold`: 32ms — high-volume entity snapshots (for example diff file maps)
enum PushLevel: String, Sendable {
    case hot
    case warm
    case cold

    /// Debounce duration per level. Single source of truth for cadence policy.
    var debounce: Duration {
        switch self {
        case .hot: .zero
        case .warm: .milliseconds(12)
        case .cold: .milliseconds(32)
        }
    }
}

// MARK: - PushOp

/// Operation type for a push envelope.
///
/// - `.merge`: partial update — React merges the payload into existing store state.
/// - `.replace`: full replacement — React replaces the entire store with the payload.
enum PushOp: String, Sendable, Encodable {
    case merge
    case replace
}

// MARK: - StoreKey

/// Identifies the target store on the React side that receives pushed data.
/// Each store maintains its own revision counter for stale-push detection.
enum StoreKey: String, Sendable, Encodable {
    case diff
    case review
    case agent
    case connection
}

// MARK: - PushTransport

/// Responsible for stamping push envelopes (revision/epoch/pushId/level/op)
/// and calling into the bridge content world.
///
/// Implemented by `BridgePaneController` in Stage 2. The protocol boundary
/// allows push pipeline components to be tested without a live WebKit instance.
@MainActor
protocol PushTransport: AnyObject {
    func pushJSON(
        store: StoreKey,
        op: PushOp,
        level: PushLevel,
        revision: Int,
        epoch: Int,
        json: Data
    ) async
}
