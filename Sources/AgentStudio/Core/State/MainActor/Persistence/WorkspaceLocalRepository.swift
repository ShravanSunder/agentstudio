import CoreGraphics
import Foundation
import GRDB

struct WorkspaceLocalRepository {
    struct ArrangementDrawerCursorKey: Hashable, Equatable {
        let arrangementId: UUID
        let drawerId: UUID
    }

    struct CursorStateRecord: Equatable {
        var activeTabId: UUID?
        var activeArrangementIdsByTabId: [UUID: UUID?]
        var activePaneIdsByArrangementId: [UUID: UUID?]
        var drawerExpansionByDrawerId: [UUID: Bool]
        var activeChildIdsByArrangementDrawer: [ArrangementDrawerCursorKey: UUID?]
    }

    struct WindowStateRecord: Equatable {
        var sidebarWidth: Double
        var windowFrame: CGRect?
    }

    struct SidebarStateRecord: Equatable {
        var filterText: String
        var isFilterVisible: Bool
        var sidebarCollapsed: Bool
        var sidebarSurface: SidebarSurface
    }

    struct WorkspaceMemoryRecord: Equatable {
        var windowState: WindowStateRecord?
        var sidebarState: SidebarStateRecord?
        var expandedGroups: Set<SidebarGroupKey>
        var recentTargets: [RecentWorkspaceTarget]
    }

    struct CacheStateRecord: Equatable {
        var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        var pullRequestCountByWorktreeId: [UUID: Int]
        var notificationCountByWorktreeId: [UUID: Int]
        var sourceRevision: UInt64
        var lastRebuiltAt: Date?

        static let empty = Self(
            repoEnrichmentByRepoId: [:],
            worktreeEnrichmentByWorktreeId: [:],
            pullRequestCountByWorktreeId: [:],
            notificationCountByWorktreeId: [:],
            sourceRevision: 0,
            lastRebuiltAt: nil
        )
    }

    let workspaceId: UUID
    let databaseWriter: any DatabaseWriter

    func migrate() throws {
        try WorkspaceLocalMigrations.migrate(databaseWriter)
    }

    func replaceCursorState(cursorState: CursorStateRecord, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceCursorRows(
                database,
                workspaceId: workspaceId,
                cursorState: cursorState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchCursorState() throws -> CursorStateRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchCursorRows(database, workspaceId: workspaceId)
        }
    }

    func setDrawerExpanded(
        drawerId: UUID,
        isExpanded: Bool,
        updatedAt: Date
    ) throws {
        try databaseWriter.write { database in
            if isExpanded {
                try database.execute(
                    sql: """
                        UPDATE local_drawer_cursor
                        SET is_expanded = 0, updated_at = ?
                        WHERE workspace_id = ? AND drawer_id != ? AND is_expanded = 1
                        """,
                    arguments: [
                        updatedAt.timeIntervalSince1970,
                        workspaceId.uuidString,
                        drawerId.uuidString,
                    ]
                )
            }
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(drawer_id) DO UPDATE SET
                        workspace_id = excluded.workspace_id,
                        is_expanded = excluded.is_expanded,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    drawerId.uuidString,
                    workspaceId.uuidString,
                    isExpanded ? 1 : 0,
                    updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func replaceWindowState(_ windowState: WindowStateRecord?, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceWindowStateRows(
                database,
                workspaceId: workspaceId,
                windowState: windowState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchWindowState() throws -> WindowStateRecord? {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchWindowStateRows(database, workspaceId: workspaceId)
        }
    }

    func replaceSidebarState(_ sidebarState: SidebarStateRecord?, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceSidebarStateRows(
                database,
                workspaceId: workspaceId,
                sidebarState: sidebarState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchSidebarState() throws -> SidebarStateRecord? {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchSidebarStateRows(database, workspaceId: workspaceId)
        }
    }

    func replaceExpandedGroups(_ expandedGroups: Set<SidebarGroupKey>, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceExpandedGroupRows(
                database,
                workspaceId: workspaceId,
                expandedGroups: expandedGroups,
                updatedAt: updatedAt
            )
        }
    }

    func fetchExpandedGroups() throws -> Set<SidebarGroupKey> {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchExpandedGroupRows(database, workspaceId: workspaceId)
        }
    }

    func replaceRecentTargets(_ recentTargets: [RecentWorkspaceTarget], updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceRecentTargetRows(
                database,
                workspaceId: workspaceId,
                recentTargets: recentTargets,
                updatedAt: updatedAt
            )
        }
    }

    func fetchRecentTargets() throws -> [RecentWorkspaceTarget] {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchRecentTargetRows(database, workspaceId: workspaceId)
        }
    }

    func replaceCacheState(cacheState: CacheStateRecord, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.deleteCacheRows(database, workspaceId: workspaceId)
            try WorkspaceLocalRepositoryStorage.insertCacheRows(
                database,
                workspaceId: workspaceId,
                cacheState: cacheState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchCacheState() throws -> CacheStateRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchCacheRows(database, workspaceId: workspaceId)
        }
    }

    func resetCacheRows() throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.deleteCacheRows(database, workspaceId: workspaceId)
        }
    }
}

enum WorkspaceLocalRepositoryError: Error, Equatable {
    case unsupportedSidebarSurface(String)
    case unsupportedRecentTargetKind(String)
    case malformedWorkspaceId(String)
    case malformedTabId(String)
    case malformedArrangementId(String)
    case malformedPaneId(String)
    case malformedDrawerId(String)
    case malformedRepoId(String)
    case malformedWorktreeId(String)
    case invalidWindowFramePayload
    case invalidCachePayload
    case missingRepoEnrichmentPayload(UUID)
    case missingWorktreeEnrichmentPayload(UUID)
}
