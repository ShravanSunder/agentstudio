import Foundation

/// Persisted snapshot of all managed pane sessions, written to disk on save
/// and loaded on launch to reconnect to surviving tmux sessions.
/// This is the authoritative pane-session registry — stores all data needed
/// to recompute and verify session IDs on startup.
struct SessionCheckpoint: Codable, Sendable {
    /// Schema version. v3 adds paneId, repoPath, worktreePath for deterministic identity.
    let version: Int
    let timestamp: Date
    let sessions: [PaneSessionData]

    init(sessions: [PaneSessionData]) {
        self.version = 3
        self.timestamp = Date()
        self.sessions = sessions
    }

    /// A single pane session's persisted state.
    struct PaneSessionData: Codable, Sendable {
        let sessionId: String
        let paneId: UUID
        let projectId: UUID
        let worktreeId: UUID
        let repoPath: URL
        let worktreePath: URL
        let displayName: String
        let workingDirectory: URL
        let lastKnownAlive: Date
    }

    // MARK: - Persistence

    /// Default checkpoint file location.
    static var defaultPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".agentstudio", isDirectory: true)
            .appendingPathComponent("session-checkpoint.json")
    }

    /// Save checkpoint to disk.
    func save(to path: URL? = nil) throws {
        let target = path ?? Self.defaultPath

        // Ensure parent directory exists
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(self)
        try data.write(to: target, options: .atomic)
    }

    /// Load checkpoint from disk. Returns nil if file doesn't exist or is unreadable.
    static func load(from path: URL? = nil) -> SessionCheckpoint? {
        let target = path ?? Self.defaultPath

        guard let data = try? Data(contentsOf: target) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(SessionCheckpoint.self, from: data)
    }

    /// Whether this checkpoint is stale (older than the given interval).
    func isStale(maxAge: TimeInterval = 7 * 24 * 60 * 60) -> Bool {
        Date().timeIntervalSince(timestamp) > maxAge
    }
}
