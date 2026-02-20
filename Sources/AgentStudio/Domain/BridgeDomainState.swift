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
}

@Observable
@MainActor
class DiffState {
    var status: DiffStatus = .idle
    var error: String?
    var epoch: Int = 0
    var manifest: DiffManifest?
}

enum DiffStatus: String, Codable, Equatable, Sendable {
    case idle, loading, ready, error
}

/// Diff manifest — metadata for files in a diff.
/// Minimal shape for Phase 2 push benchmark (100-file manifest).
struct DiffManifest: Encodable, Equatable, Sendable {
    var files: [FileManifest]
}

struct FileManifest: Encodable, Equatable, Sendable {
    let id: String
    let path: String
    let oldPath: String?
    let changeType: ChangeType
    let additions: Int
    let deletions: Int
    let size: Int
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
class SharedBridgeState {
    let connection = ConnectionState()
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
