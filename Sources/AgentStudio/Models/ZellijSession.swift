import Foundation

/// A Zellij session managed by Agent Studio
struct ZellijSession: Codable, Identifiable, Hashable, Sendable {
    /// Session ID (Zellij session name): "agentstudio--<8-char-uuid>"
    let id: String

    /// Associated project UUID
    let projectId: UUID

    /// Display name (repo name)
    let displayName: String

    /// When created
    let createdAt: Date

    /// Currently running?
    var isRunning: Bool

    /// Tabs in this session
    var tabs: [ZellijTab]

    init(
        id: String,
        projectId: UUID,
        displayName: String,
        createdAt: Date = Date(),
        isRunning: Bool = true,
        tabs: [ZellijTab] = []
    ) {
        self.id = id
        self.projectId = projectId
        self.displayName = displayName
        self.createdAt = createdAt
        self.isRunning = isRunning
        self.tabs = tabs
    }

    /// Generate session ID from project UUID
    /// Format: "agentstudio--<first-8-chars-of-uuid>"
    static func sessionId(for projectId: UUID) -> String {
        "agentstudio--\(projectId.uuidString.prefix(8).lowercased())"
    }
}

/// A tab within a Zellij session (maps to one worktree)
struct ZellijTab: Codable, Identifiable, Hashable, Sendable {
    /// Tab index (1-based, from Zellij)
    let id: Int

    /// Tab name (branch name)
    var name: String

    /// Associated worktree UUID
    let worktreeId: UUID

    /// Working directory
    let workingDirectory: URL

    /// Command to re-run on restore (e.g., "claude")
    var restoreCommand: String?

    init(
        id: Int,
        name: String,
        worktreeId: UUID,
        workingDirectory: URL,
        restoreCommand: String? = nil
    ) {
        self.id = id
        self.name = name
        self.worktreeId = worktreeId
        self.workingDirectory = workingDirectory
        self.restoreCommand = restoreCommand
    }
}
