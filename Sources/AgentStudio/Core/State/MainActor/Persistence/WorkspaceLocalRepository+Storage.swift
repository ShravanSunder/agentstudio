import CoreGraphics
import Foundation
import GRDB

enum WorkspaceLocalRepositoryStorage {
    static func replaceCursorRows(
        _ database: Database,
        workspaceId: UUID,
        cursorState: WorkspaceLocalRepository.CursorStateRecord,
        updatedAt: Date
    ) throws {
        let workspaceIdString = workspaceId.uuidString
        let updatedAtValue = updatedAt.timeIntervalSince1970
        try deleteRows(database, table: "local_workspace_cursor", workspaceIdString: workspaceIdString)
        try deleteRows(database, table: "local_tab_cursor", workspaceIdString: workspaceIdString)
        try deleteRows(database, table: "local_arrangement_cursor", workspaceIdString: workspaceIdString)
        try deleteRows(database, table: "local_drawer_cursor", workspaceIdString: workspaceIdString)
        try database.execute(
            sql: "DELETE FROM local_arrangement_drawer_cursor WHERE workspace_id = ?",
            arguments: [workspaceIdString]
        )

        try database.execute(
            sql: """
                INSERT INTO local_workspace_cursor(workspace_id, active_tab_id, updated_at)
                VALUES (?, ?, ?)
                """,
            arguments: [
                workspaceIdString,
                cursorState.activeTabId?.uuidString,
                updatedAtValue,
            ]
        )
        for (tabId, arrangementId) in cursorState.activeArrangementIdsByTabId {
            try database.execute(
                sql: """
                    INSERT INTO local_tab_cursor(tab_id, workspace_id, active_arrangement_id, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [tabId.uuidString, workspaceIdString, arrangementId?.uuidString, updatedAtValue]
            )
        }
        for (arrangementId, paneId) in cursorState.activePaneIdsByArrangementId {
            try database.execute(
                sql: """
                    INSERT INTO local_arrangement_cursor(arrangement_id, workspace_id, active_pane_id, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [arrangementId.uuidString, workspaceIdString, paneId?.uuidString, updatedAtValue]
            )
        }
        for (drawerId, isExpanded) in cursorState.drawerExpansionByDrawerId {
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [drawerId.uuidString, workspaceIdString, isExpanded ? 1 : 0, updatedAtValue]
            )
        }
        for (key, activeChildId) in cursorState.activeChildIdsByArrangementDrawer {
            try database.execute(
                sql: """
                    INSERT INTO local_arrangement_drawer_cursor(
                        arrangement_id, drawer_id, workspace_id, active_child_id, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    key.arrangementId.uuidString,
                    key.drawerId.uuidString,
                    workspaceIdString,
                    activeChildId?.uuidString,
                    updatedAtValue,
                ]
            )
        }
    }

    static func fetchCursorRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> WorkspaceLocalRepository.CursorStateRecord {
        let workspaceIdString = workspaceId.uuidString
        let activeTabIdString = try String.fetchOne(
            database,
            sql: """
                SELECT active_tab_id
                FROM local_workspace_cursor
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        let tabRows = try Row.fetchAll(
            database,
            sql: """
                SELECT tab_id, active_arrangement_id
                FROM local_tab_cursor
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        let arrangementRows = try Row.fetchAll(
            database,
            sql: """
                SELECT arrangement_id, active_pane_id
                FROM local_arrangement_cursor
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        let drawerRows = try Row.fetchAll(
            database,
            sql: """
                SELECT drawer_id, is_expanded
                FROM local_drawer_cursor
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        let arrangementDrawerRows = try Row.fetchAll(
            database,
            sql: """
                SELECT arrangement_id, drawer_id, active_child_id
                FROM local_arrangement_drawer_cursor
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )

        return try WorkspaceLocalRepository.CursorStateRecord(
            activeTabId: activeTabIdString.map {
                try WorkspaceLocalRepositoryCodecs.uuid($0, WorkspaceLocalRepositoryError.malformedTabId)
            },
            activeArrangementIdsByTabId: activeArrangementIdsByTabId(from: tabRows),
            activePaneIdsByArrangementId: activePaneIdsByArrangementId(from: arrangementRows),
            drawerExpansionByDrawerId: drawerExpansionByDrawerId(from: drawerRows),
            activeChildIdsByArrangementDrawer: activeChildIdsByArrangementDrawer(from: arrangementDrawerRows)
        )
    }

    private static func activeArrangementIdsByTabId(from rows: [Row]) throws -> [UUID: UUID?] {
        try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let tabId = try WorkspaceLocalRepositoryCodecs.uuid(
                    row["tab_id"],
                    WorkspaceLocalRepositoryError.malformedTabId
                )
                let arrangementIdString: String? = row["active_arrangement_id"]
                return (
                    tabId,
                    try arrangementIdString.map {
                        try WorkspaceLocalRepositoryCodecs.uuid(
                            $0,
                            WorkspaceLocalRepositoryError.malformedArrangementId
                        )
                    }
                )
            }
        )
    }

    private static func activePaneIdsByArrangementId(from rows: [Row]) throws -> [UUID: UUID?] {
        try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let arrangementId = try WorkspaceLocalRepositoryCodecs.uuid(
                    row["arrangement_id"],
                    WorkspaceLocalRepositoryError.malformedArrangementId
                )
                let paneIdString: String? = row["active_pane_id"]
                return (
                    arrangementId,
                    try paneIdString.map {
                        try WorkspaceLocalRepositoryCodecs.uuid($0, WorkspaceLocalRepositoryError.malformedPaneId)
                    }
                )
            }
        )
    }

    private static func drawerExpansionByDrawerId(from rows: [Row]) throws -> [UUID: Bool] {
        try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let drawerId = try WorkspaceLocalRepositoryCodecs.uuid(
                    row["drawer_id"],
                    WorkspaceLocalRepositoryError.malformedDrawerId
                )
                let isExpanded: Int = row["is_expanded"]
                return (drawerId, isExpanded == 1)
            }
        )
    }

    private static func activeChildIdsByArrangementDrawer(
        from rows: [Row]
    ) throws -> [WorkspaceLocalRepository.ArrangementDrawerCursorKey: UUID?] {
        try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let arrangementId = try WorkspaceLocalRepositoryCodecs.uuid(
                    row["arrangement_id"],
                    WorkspaceLocalRepositoryError.malformedArrangementId
                )
                let drawerId = try WorkspaceLocalRepositoryCodecs.uuid(
                    row["drawer_id"],
                    WorkspaceLocalRepositoryError.malformedDrawerId
                )
                let activeChildIdString: String? = row["active_child_id"]
                return (
                    .init(arrangementId: arrangementId, drawerId: drawerId),
                    try activeChildIdString.map {
                        try WorkspaceLocalRepositoryCodecs.uuid($0, WorkspaceLocalRepositoryError.malformedPaneId)
                    }
                )
            }
        )
    }

    static func replaceWorkspaceMemoryRows(
        _ database: Database,
        workspaceId: UUID,
        memoryState: WorkspaceLocalRepository.WorkspaceMemoryRecord,
        updatedAt: Date
    ) throws {
        let workspaceIdString = workspaceId.uuidString
        let updatedAtValue = updatedAt.timeIntervalSince1970
        try deleteRows(database, table: "local_workspace_window_state", workspaceIdString: workspaceIdString)
        try deleteRows(database, table: "local_sidebar_state", workspaceIdString: workspaceIdString)
        try deleteRows(database, table: "local_sidebar_expanded_group", workspaceIdString: workspaceIdString)
        try deleteRows(database, table: "local_recent_workspace_target", workspaceIdString: workspaceIdString)

        if let windowState = memoryState.windowState {
            try database.execute(
                sql: """
                    INSERT INTO local_workspace_window_state(
                        workspace_id, sidebar_width, window_frame_json, updated_at
                    )
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceIdString,
                    windowState.sidebarWidth,
                    try WorkspaceLocalRepositoryCodecs.encodeWindowFrame(windowState.windowFrame),
                    updatedAtValue,
                ]
            )
        }
        if let sidebarState = memoryState.sidebarState {
            try database.execute(
                sql: """
                    INSERT INTO local_sidebar_state(
                        workspace_id, filter_text, is_filter_visible, sidebar_collapsed, sidebar_surface, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceIdString,
                    sidebarState.filterText,
                    sidebarState.isFilterVisible ? 1 : 0,
                    sidebarState.sidebarCollapsed ? 1 : 0,
                    SQLiteLocalUXStorage.storageValue(for: sidebarState.sidebarSurface),
                    updatedAtValue,
                ]
            )
        }
        for groupKey in memoryState.expandedGroups {
            try database.execute(
                sql: """
                    INSERT INTO local_sidebar_expanded_group(workspace_id, group_key)
                    VALUES (?, ?)
                    """,
                arguments: [workspaceIdString, groupKey.rawValue]
            )
        }
        for target in memoryState.recentTargets {
            try WorkspaceLocalRepositoryCodecs.insertRecentWorkspaceTarget(
                database,
                workspaceIdString: workspaceIdString,
                target: target
            )
        }
    }

    static func fetchWorkspaceMemoryRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> WorkspaceLocalRepository.WorkspaceMemoryRecord {
        let workspaceIdString = workspaceId.uuidString
        let windowState = try WorkspaceLocalRepositoryCodecs.fetchWindowState(
            database,
            workspaceIdString: workspaceIdString
        )
        let sidebarState = try WorkspaceLocalRepositoryCodecs.fetchSidebarState(
            database,
            workspaceIdString: workspaceIdString
        )
        let expandedGroupValues = try String.fetchAll(
            database,
            sql: """
                SELECT group_key
                FROM local_sidebar_expanded_group
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        let expandedGroups: Set<SidebarGroupKey> = Set(
            expandedGroupValues.map { rawValue in SidebarGroupKey(rawValue) }
        )
        let recentTargets = try WorkspaceLocalRepositoryCodecs.fetchRecentWorkspaceTargets(
            database,
            workspaceIdString: workspaceIdString
        )
        return .init(
            windowState: windowState,
            sidebarState: sidebarState,
            expandedGroups: expandedGroups,
            recentTargets: recentTargets
        )
    }

    static func deleteCacheRows(_ database: Database, workspaceId: UUID) throws {
        let workspaceIdString = workspaceId.uuidString
        for table in [
            "cache_metadata",
            "cache_repo_enrichment",
            "cache_worktree_enrichment",
            "cache_pull_request_count",
            "cache_notification_count",
        ] {
            try database.execute(sql: "DELETE FROM \(table) WHERE workspace_id = ?", arguments: [workspaceIdString])
        }
    }

    static func insertCacheRows(
        _ database: Database,
        workspaceId: UUID,
        cacheState: WorkspaceLocalRepository.CacheStateRecord,
        updatedAt: Date
    ) throws {
        let workspaceIdString = workspaceId.uuidString
        let updatedAtValue = updatedAt.timeIntervalSince1970
        try database.execute(
            sql: """
                INSERT INTO cache_metadata(workspace_id, source_revision, last_rebuilt_at)
                VALUES (?, ?, ?)
                """,
            arguments: [
                workspaceIdString,
                Int64(cacheState.sourceRevision),
                cacheState.lastRebuiltAt?.timeIntervalSince1970,
            ]
        )
        for enrichment in cacheState.repoEnrichmentByRepoId.values {
            try WorkspaceLocalRepositoryCodecs.insertRepoEnrichment(
                database,
                workspaceIdString: workspaceIdString,
                enrichment: enrichment,
                updatedAt: updatedAt
            )
        }
        for enrichment in cacheState.worktreeEnrichmentByWorktreeId.values {
            try WorkspaceLocalRepositoryCodecs.insertWorktreeEnrichment(
                database,
                workspaceIdString: workspaceIdString,
                enrichment: enrichment
            )
        }
        for (worktreeId, count) in cacheState.pullRequestCountByWorktreeId {
            try WorkspaceLocalRepositoryCodecs.insertCount(
                database,
                table: .pullRequest,
                row: .init(
                    workspaceIdString: workspaceIdString,
                    worktreeId: worktreeId,
                    repoId: cacheState.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId,
                    count: count,
                    updatedAtValue: updatedAtValue
                )
            )
        }
        for (worktreeId, count) in cacheState.notificationCountByWorktreeId {
            try WorkspaceLocalRepositoryCodecs.insertCount(
                database,
                table: .notification,
                row: .init(
                    workspaceIdString: workspaceIdString,
                    worktreeId: worktreeId,
                    repoId: cacheState.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId,
                    count: count,
                    updatedAtValue: updatedAtValue
                )
            )
        }
    }

    static func fetchCacheRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> WorkspaceLocalRepository.CacheStateRecord {
        let workspaceIdString = workspaceId.uuidString
        let metadataRow = try Row.fetchOne(
            database,
            sql: """
                SELECT source_revision, last_rebuilt_at
                FROM cache_metadata
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        let repoEnrichments = try WorkspaceLocalRepositoryCodecs.fetchRepoEnrichments(
            database,
            workspaceIdString: workspaceIdString
        )
        let worktreeEnrichments = try WorkspaceLocalRepositoryCodecs.fetchWorktreeEnrichments(
            database,
            workspaceIdString: workspaceIdString
        )
        let pullRequestCounts = try WorkspaceLocalRepositoryCodecs.fetchCounts(
            database,
            table: .pullRequest,
            workspaceIdString: workspaceIdString
        )
        let notificationCounts = try WorkspaceLocalRepositoryCodecs.fetchCounts(
            database,
            table: .notification,
            workspaceIdString: workspaceIdString
        )
        let sourceRevisionValue: Int64 = metadataRow?["source_revision"] ?? 0
        let lastRebuiltAtValue: Double? = metadataRow?["last_rebuilt_at"]
        return .init(
            repoEnrichmentByRepoId: repoEnrichments,
            worktreeEnrichmentByWorktreeId: worktreeEnrichments,
            pullRequestCountByWorktreeId: pullRequestCounts,
            notificationCountByWorktreeId: notificationCounts,
            sourceRevision: UInt64(sourceRevisionValue),
            lastRebuiltAt: lastRebuiltAtValue.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func deleteRows(
        _ database: Database,
        table: String,
        workspaceIdString: String
    ) throws {
        try database.execute(
            sql: "DELETE FROM \(table) WHERE workspace_id = ?",
            arguments: [workspaceIdString]
        )
    }
}
