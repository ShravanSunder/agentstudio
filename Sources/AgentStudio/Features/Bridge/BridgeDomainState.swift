import Foundation
import Observation

/// Root domain state per bridge pane.
/// Full model defined in design doc section 8 (line 1440).
/// This is the minimal set needed for Phase 2 push pipeline testing.
@Observable
@MainActor
class PaneDomainState {
    let diff = DiffState()
    let review = ReviewState()
    let connection = ConnectionState()
    private(set) var commandAcks: [String: CommandAck] = [:]

    func recordAck(_ ack: CommandAck) {
        commandAcks[ack.commandId] = ack
    }

    func clearAcks() {
        commandAcks.removeAll()
    }
}

@Observable
@MainActor
class DiffState {
    var status: DiffStatus = .idle
    var error: String?
    var epoch: Int = 0
    var files: [String: FileManifest] = [:]
}

enum DiffStatus: String, Codable, Equatable, Sendable {
    case idle, loading, ready, error
}

struct FileManifest: Encodable, Equatable, Sendable {
    let id: String
    /// Monotonic version counter for EntitySlice change detection.
    ///
    /// **Contract**: Callers MUST increment `version` whenever any mutable field
    /// (`additions`, `deletions`, `size`) changes. EntitySlice compares this value
    /// to detect per-entity changes — if `version` is not bumped, the change is
    /// silently skipped and React sees stale data.
    var version: Int
    let path: String
    let oldPath: String?
    let changeType: ChangeType
    var additions: Int
    var deletions: Int
    var size: Int
    let contextHash: String

    enum ChangeType: String, Encodable, Equatable, Sendable {
        case added, modified, deleted, renamed
    }
}

@Observable
@MainActor
class ReviewState {
    var threads: [UUID: ReviewThread] = [:]
    var viewedFiles: Set<String> = []
}

/// Minimal review thread for push pipeline testing.
struct ReviewThread: Encodable {
    let id: UUID
    var version: Int
    var body: String
}

@Observable
@MainActor
class ConnectionState {
    var health: ConnectionHealth = .connected
    var latencyMs: Int = 0

    enum ConnectionHealth: String, Codable, Equatable, Sendable {
        case connected, disconnected, error
    }
}
