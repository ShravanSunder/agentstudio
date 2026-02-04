import Foundation

/// Checkpoint for reboot recovery - serialized to disk when app quits
struct SessionCheckpoint: Codable, Sendable {
    /// Schema version for future migrations
    let version: Int

    /// When checkpoint was created
    let timestamp: Date

    /// Session data to restore
    let sessions: [SessionData]

    /// Flattened session data for serialization
    struct SessionData: Codable, Sendable {
        let id: String
        let projectId: UUID
        let displayName: String
        let tabs: [TabData]
    }

    /// Flattened tab data for serialization
    struct TabData: Codable, Sendable {
        let id: Int
        let name: String
        let worktreeId: UUID
        let workingDirectory: String
        let restoreCommand: String?
    }

    /// Create checkpoint from active sessions
    init(sessions: [ZellijSession]) {
        self.version = 1
        self.timestamp = Date()
        self.sessions = sessions.map { session in
            SessionData(
                id: session.id,
                projectId: session.projectId,
                displayName: session.displayName,
                tabs: session.tabs.map { tab in
                    TabData(
                        id: tab.id,
                        name: tab.name,
                        worktreeId: tab.worktreeId,
                        workingDirectory: tab.workingDirectory.path,
                        restoreCommand: tab.restoreCommand
                    )
                }
            )
        }
    }
}
