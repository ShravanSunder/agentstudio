// SessionCheckpoint.swift
// AgentStudio
//
// Checkpoint for session restore - serialized to disk when app quits.
// Version 2 adds: order field for tabs, lastKnownAlive, zellijSocketDir.

import Foundation

// MARK: - Session Checkpoint

/// Checkpoint for reboot recovery - serialized to disk when app quits.
struct SessionCheckpoint: Codable, Sendable {

    // MARK: - Version

    /// Current schema version
    static let currentVersion = 2

    /// Schema version for migrations
    let version: Int

    /// When checkpoint was created
    let timestamp: Date

    /// Session data to restore
    let sessions: [SessionData]

    /// Socket directory (for validation on restore)
    let zellijSocketDir: String?

    // MARK: - Nested Types

    /// Flattened session data for serialization
    struct SessionData: Codable, Sendable {
        let id: String
        let projectId: UUID
        let displayName: String
        let repoPath: String?
        let tabs: [TabData]
        let lastKnownAlive: Date?

        init(
            id: String,
            projectId: UUID,
            displayName: String,
            repoPath: String? = nil,
            tabs: [TabData],
            lastKnownAlive: Date? = nil
        ) {
            self.id = id
            self.projectId = projectId
            self.displayName = displayName
            self.repoPath = repoPath
            self.tabs = tabs
            self.lastKnownAlive = lastKnownAlive
        }
    }

    /// Flattened tab data for serialization
    struct TabData: Codable, Sendable {
        let id: Int
        let name: String
        let worktreeId: UUID
        let workingDirectory: String
        let restoreCommand: String?
        let order: Int?

        init(
            id: Int,
            name: String,
            worktreeId: UUID,
            workingDirectory: String,
            restoreCommand: String? = nil,
            order: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.worktreeId = worktreeId
            self.workingDirectory = workingDirectory
            self.restoreCommand = restoreCommand
            self.order = order
        }
    }

    // MARK: - Initialization

    /// Create a new checkpoint with current version
    init(
        version: Int = currentVersion,
        timestamp: Date = Date(),
        sessions: [SessionData],
        zellijSocketDir: String? = nil
    ) {
        self.version = version
        self.timestamp = timestamp
        self.sessions = sessions
        self.zellijSocketDir = zellijSocketDir
    }

    /// Create checkpoint from active ZellijSessions (backward compatibility)
    init(sessions: [ZellijSession]) {
        self.version = Self.currentVersion
        self.timestamp = Date()
        self.zellijSocketDir = nil
        self.sessions = sessions.map { session in
            SessionData(
                id: session.id,
                projectId: session.projectId,
                displayName: session.displayName,
                repoPath: nil, // Legacy sessions don't have repoPath
                tabs: session.tabs.map { tab in
                    TabData(
                        id: tab.id,
                        name: tab.name,
                        worktreeId: tab.worktreeId,
                        workingDirectory: tab.workingDirectory.path,
                        restoreCommand: tab.restoreCommand,
                        order: tab.id // Use tab id as order for legacy
                    )
                },
                lastKnownAlive: Date()
            )
        }
    }

    // MARK: - Decoding with Migration

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decode(Int.self, forKey: .version)
        self.version = version
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Handle v1 → v2 migration
        if version < 2 {
            // v1 format: no zellijSocketDir, no order, no lastKnownAlive, no repoPath
            self.zellijSocketDir = nil

            let v1Sessions = try container.decode([SessionDataV1].self, forKey: .sessions)
            self.sessions = v1Sessions.map { v1Session in
                SessionData(
                    id: v1Session.id,
                    projectId: v1Session.projectId,
                    displayName: v1Session.displayName,
                    repoPath: nil, // Not available in v1
                    tabs: v1Session.tabs.map { v1Tab in
                        TabData(
                            id: v1Tab.id,
                            name: v1Tab.name,
                            worktreeId: v1Tab.worktreeId,
                            workingDirectory: v1Tab.workingDirectory,
                            restoreCommand: v1Tab.restoreCommand,
                            order: v1Tab.id // Use tab id as order for v1
                        )
                    },
                    lastKnownAlive: nil
                )
            }
        } else {
            // v2+ format
            self.zellijSocketDir = try container.decodeIfPresent(String.self, forKey: .zellijSocketDir)
            self.sessions = try container.decode([SessionData].self, forKey: .sessions)
        }
    }

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case version
        case timestamp
        case sessions
        case zellijSocketDir
    }
}

// MARK: - V1 Types (for migration)

/// V1 session data format
private struct SessionDataV1: Codable {
    let id: String
    let projectId: UUID
    let displayName: String
    let tabs: [TabDataV1]
}

/// V1 tab data format
private struct TabDataV1: Codable {
    let id: Int
    let name: String
    let worktreeId: UUID
    let workingDirectory: String
    let restoreCommand: String?
}

// MARK: - Convenience

extension SessionCheckpoint {
    /// Check if checkpoint is stale (older than given interval)
    func isStale(olderThan interval: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) > interval
    }

    /// Get sessions sorted by last known alive time
    var sessionsSortedByRecency: [SessionData] {
        sessions.sorted { s1, s2 in
            let t1 = s1.lastKnownAlive ?? .distantPast
            let t2 = s2.lastKnownAlive ?? .distantPast
            return t1 > t2
        }
    }
}
