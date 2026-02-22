import Foundation
import Observation

/// Root domain state per bridge pane.
/// Full model defined in design doc section 8 (line 1440).
/// This is the minimal set needed for Phase 2 push pipeline testing.
@Observable
@MainActor
final class PaneDomainState {
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
final class DiffState {
    private(set) var status: DiffStatus = .idle
    private(set) var error: String?
    private(set) var epoch: Int = 0
    private(set) var files: [String: FileManifest] = [:]

    func setStatus(_ status: DiffStatus, error: String? = nil) {
        self.status = status
        self.error = error
    }

    func setError(_ error: String?) {
        self.error = error
    }

    func setEpoch(_ epoch: Int) {
        self.epoch = epoch
    }

    func advanceEpoch() {
        epoch += 1
    }

    func replaceFiles(_ files: [String: FileManifest]) {
        self.files = files
    }

    func setFile(_ file: FileManifest) {
        files[file.id] = file
    }

    func mutateFile(id: String, _ transform: (inout FileManifest) -> Void) {
        guard var file = files[id] else { return }
        transform(&file)
        files[id] = file
    }
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
final class ReviewState {
    private(set) var threads: [UUID: ReviewThread] = [:]
    private(set) var viewedFiles: Set<String> = []

    func setThreads(_ threads: [UUID: ReviewThread]) {
        self.threads = threads
    }

    func upsertThread(_ thread: ReviewThread) {
        threads[thread.id] = thread
    }

    func removeThread(id: UUID) {
        threads.removeValue(forKey: id)
    }

    func markFileViewed(_ fileId: String) {
        viewedFiles.insert(fileId)
    }

    func unmarkFileViewed(_ fileId: String) {
        viewedFiles.remove(fileId)
    }
}

/// Minimal review thread for push pipeline testing.
struct ReviewThread: Encodable, Sendable {
    let id: UUID
    var version: Int
    var body: String
}

@Observable
@MainActor
final class ConnectionState {
    private(set) var health: ConnectionHealth = .connected
    private(set) var latencyMs: Int = 0

    func setHealth(_ health: ConnectionHealth) {
        self.health = health
    }

    func setLatencyMs(_ latencyMs: Int) {
        self.latencyMs = latencyMs
    }

    func setConnection(health: ConnectionHealth, latencyMs: Int) {
        self.health = health
        self.latencyMs = latencyMs
    }

    enum ConnectionHealth: String, Codable, Equatable, Sendable {
        case connected, disconnected, error
    }
}
