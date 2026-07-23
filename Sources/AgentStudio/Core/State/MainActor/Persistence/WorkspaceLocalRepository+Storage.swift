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
        for table in [
            "local_workspace_cursor",
            "local_tab_cursor",
            "local_arrangement_cursor",
            "local_drawer_cursor",
            "local_arrangement_drawer_cursor",
        ] {
            try deleteWorkspaceRows(database, table: table, workspaceIdString: workspaceIdString)
        }
        try database.execute(
            sql: """
                INSERT INTO local_workspace_cursor(workspace_id, active_tab_id, updated_at)
                VALUES (?, ?, ?)
                """,
            arguments: [workspaceIdString, cursorState.activeTabId?.uuidString, updatedAtValue]
        )
        for (tabId, arrangementId) in cursorState.activeArrangementIdsByTabId {
            try database.execute(
                sql: """
                    INSERT INTO local_tab_cursor(workspace_id, tab_id, active_arrangement_id, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [workspaceIdString, tabId.uuidString, arrangementId.uuidString, updatedAtValue]
            )
        }
        for (arrangementId, paneId) in cursorState.activePaneIdsByArrangementId {
            try database.execute(
                sql: """
                    INSERT INTO local_arrangement_cursor(workspace_id, arrangement_id, active_pane_id, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [workspaceIdString, arrangementId.uuidString, paneId.uuidString, updatedAtValue]
            )
        }
        for (drawerId, isExpanded) in cursorState.drawerExpansionByDrawerId {
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(workspace_id, drawer_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [workspaceIdString, drawerId.uuidString, isExpanded ? 1 : 0, updatedAtValue]
            )
        }
        for (key, activeChildId) in cursorState.activeChildIdsByArrangementDrawer {
            try database.execute(
                sql: """
                    INSERT INTO local_arrangement_drawer_cursor(
                        workspace_id, arrangement_id, drawer_id, active_child_id, updated_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceIdString,
                    key.arrangementId.uuidString,
                    key.drawerId.uuidString,
                    activeChildId.uuidString,
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
            sql: "SELECT active_tab_id FROM local_workspace_cursor WHERE workspace_id = ?",
            arguments: [workspaceIdString]
        )
        let tabRows = try Row.fetchAll(
            database,
            sql: "SELECT tab_id, active_arrangement_id FROM local_tab_cursor WHERE workspace_id = ?",
            arguments: [workspaceIdString]
        )
        let arrangementRows = try Row.fetchAll(
            database,
            sql: "SELECT arrangement_id, active_pane_id FROM local_arrangement_cursor WHERE workspace_id = ?",
            arguments: [workspaceIdString]
        )
        let drawerRows = try Row.fetchAll(
            database,
            sql: "SELECT drawer_id, is_expanded FROM local_drawer_cursor WHERE workspace_id = ?",
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
        return .init(
            activeTabId: try activeTabIdString.map {
                try WorkspaceLocalRepositoryCodecs.uuid($0, WorkspaceLocalRepositoryError.malformedTabId)
            },
            activeArrangementIdsByTabId: try activeArrangementIdsByTabId(from: tabRows),
            activePaneIdsByArrangementId: try activePaneIdsByArrangementId(from: arrangementRows),
            drawerExpansionByDrawerId: try drawerExpansionByDrawerId(from: drawerRows),
            activeChildIdsByArrangementDrawer: try activeChildIdsByArrangementDrawer(from: arrangementDrawerRows)
        )
    }

    static func replaceWindowStateRows(
        _ database: Database,
        workspaceId _: UUID,
        windowState: WorkspaceLocalRepository.WindowStateRecord?,
        updatedAt: Date
    ) throws {
        guard let windowState else {
            try resetWindowPresentation(database, updatedAt: updatedAt)
            return
        }
        let windowId = try ensureMainWindowRow(database, updatedAt: updatedAt)
        try database.execute(
            sql: """
                UPDATE local_window_state
                SET sidebar_width = ?, window_frame_json = ?, updated_at = ?
                WHERE window_id = ?
                """,
            arguments: [
                windowState.sidebarWidth,
                try WorkspaceLocalRepositoryCodecs.encodeWindowFrame(windowState.windowFrame),
                updatedAt.timeIntervalSince1970,
                windowId,
            ]
        )
    }

    static func fetchWindowStateRows(
        _ database: Database,
        workspaceId _: UUID
    ) throws -> WorkspaceLocalRepository.WindowStateRecord? {
        try WorkspaceLocalRepositoryCodecs.fetchWindowState(database)
    }

    static func replaceSidebarStateRows(
        _ database: Database,
        workspaceId _: UUID,
        sidebarState: WorkspaceLocalRepository.SidebarStateRecord?,
        updatedAt: Date
    ) throws {
        let windowId = try ensureMainWindowRow(database, updatedAt: updatedAt)
        let sidebarState =
            sidebarState
            ?? .init(
                filterText: "",
                isFilterVisible: false,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            )
        try database.execute(
            sql: """
                UPDATE local_window_state
                SET filter_text = ?, is_filter_visible = ?, sidebar_collapsed = ?,
                    sidebar_surface = ?, updated_at = ?
                WHERE window_id = ?
                """,
            arguments: [
                sidebarState.filterText,
                sidebarState.isFilterVisible ? 1 : 0,
                sidebarState.sidebarCollapsed ? 1 : 0,
                SQLiteLocalUXStorage.storageValue(for: sidebarState.sidebarSurface),
                updatedAt.timeIntervalSince1970,
                windowId,
            ]
        )
    }

    static func fetchSidebarStateRows(
        _ database: Database,
        workspaceId _: UUID
    ) throws -> WorkspaceLocalRepository.SidebarStateRecord? {
        try WorkspaceLocalRepositoryCodecs.fetchSidebarState(database)
    }

    static func replaceExpandedGroupRows(
        _ database: Database,
        workspaceId _: UUID,
        expandedGroups: Set<SidebarGroupKey>,
        updatedAt: Date
    ) throws {
        let windowId = try ensureMainWindowRow(database, updatedAt: updatedAt)
        try database.execute(
            sql: "DELETE FROM local_window_sidebar_expanded_group WHERE window_id = ?",
            arguments: [windowId]
        )
        for groupKey in expandedGroups {
            try database.execute(
                sql: """
                    INSERT INTO local_window_sidebar_expanded_group(window_id, group_key)
                    VALUES (?, ?)
                    """,
                arguments: [windowId, groupKey.rawValue]
            )
        }
    }

    static func fetchExpandedGroupRows(
        _ database: Database,
        workspaceId _: UUID
    ) throws -> Set<SidebarGroupKey> {
        let values = try String.fetchAll(
            database,
            sql: """
                SELECT group_key
                FROM local_window_sidebar_expanded_group AS expanded
                JOIN local_window_state AS window ON window.window_id = expanded.window_id
                WHERE window.window_role = 'main'
                """
        )
        return Set<SidebarGroupKey>(values.map { SidebarGroupKey($0) })
    }

    static func replaceRecentTargetRows(
        _ database: Database,
        workspaceId: UUID,
        recentTargets: [RecentWorkspaceTarget],
        updatedAt _: Date
    ) throws {
        let workspaceIdString = workspaceId.uuidString
        try deleteWorkspaceRows(
            database,
            table: "local_recent_workspace_target",
            workspaceIdString: workspaceIdString
        )
        for target in recentTargets {
            try WorkspaceLocalRepositoryCodecs.insertRecentWorkspaceTarget(
                database,
                workspaceIdString: workspaceIdString,
                target: target
            )
        }
    }

    static func fetchRecentTargetRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> [RecentWorkspaceTarget] {
        try WorkspaceLocalRepositoryCodecs.fetchRecentWorkspaceTargets(
            database,
            workspaceIdString: workspaceId.uuidString
        )
    }

    static func deleteCacheRows(_ database: Database, workspaceId _: UUID) throws {
        for table in [
            "cache_metadata",
            "cache_repo_enrichment",
            "cache_worktree_enrichment",
            "cache_pull_request_count",
        ] {
            try database.execute(sql: "DELETE FROM \(table)")
        }
    }

    static func insertCacheRows(
        _ database: Database,
        workspaceId _: UUID,
        cacheState: WorkspaceLocalRepository.CacheStateRecord,
        updatedAt: Date
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO cache_metadata(singleton_id, source_revision, last_rebuilt_at)
                VALUES (1, ?, ?)
                """,
            arguments: [Int64(cacheState.sourceRevision), cacheState.lastRebuiltAt?.timeIntervalSince1970]
        )
        for enrichment in cacheState.repoEnrichmentByRepoId.values {
            try WorkspaceLocalRepositoryCodecs.insertRepoEnrichment(
                database,
                enrichment: enrichment,
                updatedAt: updatedAt
            )
        }
        for enrichment in cacheState.worktreeEnrichmentByWorktreeId.values {
            try WorkspaceLocalRepositoryCodecs.insertWorktreeEnrichment(database, enrichment: enrichment)
        }
        for (worktreeId, count) in cacheState.pullRequestCountByWorktreeId {
            try WorkspaceLocalRepositoryCodecs.insertPullRequestCount(
                database,
                row: .init(
                    worktreeId: worktreeId,
                    repoId: cacheState.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId,
                    count: count,
                    updatedAtValue: updatedAt.timeIntervalSince1970
                )
            )
        }
    }

    static func fetchCacheRows(
        _ database: Database,
        workspaceId _: UUID
    ) throws -> WorkspaceLocalRepository.CacheStateRecord {
        let metadataRow = try Row.fetchOne(
            database,
            sql: "SELECT source_revision, last_rebuilt_at FROM cache_metadata WHERE singleton_id = 1"
        )
        let sourceRevisionValue: Int64 = metadataRow?["source_revision"] ?? 0
        let lastRebuiltAtValue: Double? = metadataRow?["last_rebuilt_at"]
        return .init(
            repoEnrichmentByRepoId: try WorkspaceLocalRepositoryCodecs.fetchRepoEnrichments(database),
            worktreeEnrichmentByWorktreeId: try WorkspaceLocalRepositoryCodecs.fetchWorktreeEnrichments(database),
            pullRequestCountByWorktreeId: try WorkspaceLocalRepositoryCodecs.fetchPullRequestCounts(database),
            sourceRevision: UInt64(sourceRevisionValue),
            lastRebuiltAt: lastRebuiltAtValue.map(Date.init(timeIntervalSince1970:))
        )
    }

    static func hasSidebarStateRows(_ database: Database, workspaceId _: UUID) throws -> Bool {
        try mainWindowExists(database)
    }

    static func hasExpandedGroupStateRows(_ database: Database, workspaceId _: UUID) throws -> Bool {
        try mainWindowExists(database)
    }

    static func hasRecentTargetStateRows(_ database: Database, workspaceId: UUID) throws -> Bool {
        try workspaceRowExists(database, table: "local_recent_workspace_target", workspaceId: workspaceId)
    }

    static func hasCacheStateRows(_ database: Database, workspaceId _: UUID) throws -> Bool {
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cache_metadata WHERE singleton_id = 1") == 1
    }

    static func replaceEditorPreferencesRows(
        _ database: Database,
        workspaceId: UUID,
        preferences: WorkspaceLocalRepository.EditorPreferencesRecord,
        updatedAt: Date
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_editor_preferences(workspace_id, bookmarked_editor_id, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(workspace_id) DO UPDATE SET
                    bookmarked_editor_id = excluded.bookmarked_editor_id,
                    updated_at = excluded.updated_at
                """,
            arguments: [workspaceId.uuidString, preferences.bookmarkedEditorId, updatedAt.timeIntervalSince1970]
        )
    }

    static func fetchEditorPreferencesRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> WorkspaceLocalRepository.EditorPreferencesRecord {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT bookmarked_editor_id FROM local_editor_preferences WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        else {
            return .default
        }
        return .init(bookmarkedEditorId: row["bookmarked_editor_id"])
    }

    static func replaceRepoExplorerPreferencesRows(
        _ database: Database,
        workspaceId: UUID,
        preferences: WorkspaceLocalRepository.RepoExplorerPreferencesRecord,
        updatedAt: Date
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_repo_explorer_preferences(
                    workspace_id, grouping_mode, sort_order, visibility_mode, updated_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(workspace_id) DO UPDATE SET
                    grouping_mode = excluded.grouping_mode,
                    sort_order = excluded.sort_order,
                    visibility_mode = excluded.visibility_mode,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                workspaceId.uuidString,
                SQLiteLocalUXStorage.storageValue(for: preferences.groupingMode),
                SQLiteLocalUXStorage.storageValue(for: preferences.sortOrder),
                SQLiteLocalUXStorage.storageValue(for: preferences.visibilityMode),
                updatedAt.timeIntervalSince1970,
            ]
        )
    }

    static func fetchRepoExplorerPreferencesRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> WorkspaceLocalRepository.RepoExplorerPreferencesRecord {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT grouping_mode, sort_order, visibility_mode
                    FROM local_repo_explorer_preferences
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            ),
            let groupingMode = RepoExplorerGroupingMode(rawValue: row["grouping_mode"]),
            let sortOrder = RepoExplorerSortOrder(rawValue: row["sort_order"]),
            let visibilityMode = RepoExplorerVisibilityMode(rawValue: row["visibility_mode"])
        else {
            return .default
        }
        return .init(groupingMode: groupingMode, sortOrder: sortOrder, visibilityMode: visibilityMode)
    }

    static func replaceInboxNotificationPreferencesRows(
        _ database: Database,
        workspaceId: UUID,
        preferences: WorkspaceLocalRepository.InboxNotificationPreferencesRecord,
        updatedAt: Date
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_inbox_notification_preferences(
                    workspace_id, grouping, sort_order, bell_enabled, global_content_mode,
                    global_row_state_filter, pane_content_mode, pane_row_state_filter, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(workspace_id) DO UPDATE SET
                    grouping = excluded.grouping,
                    sort_order = excluded.sort_order,
                    bell_enabled = excluded.bell_enabled,
                    global_content_mode = excluded.global_content_mode,
                    global_row_state_filter = excluded.global_row_state_filter,
                    pane_content_mode = excluded.pane_content_mode,
                    pane_row_state_filter = excluded.pane_row_state_filter,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                workspaceId.uuidString,
                SQLiteLocalUXStorage.storageValue(for: preferences.grouping),
                SQLiteLocalUXStorage.storageValue(for: preferences.sortOrder),
                preferences.bellEnabled ? 1 : 0,
                SQLiteLocalUXStorage.storageValue(for: preferences.globalContentMode),
                SQLiteLocalUXStorage.storageValue(for: preferences.globalRowStateFilter),
                SQLiteLocalUXStorage.storageValue(for: preferences.paneContentMode),
                SQLiteLocalUXStorage.storageValue(for: preferences.paneRowStateFilter),
                updatedAt.timeIntervalSince1970,
            ]
        )
    }

    static func fetchInboxNotificationPreferencesRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> WorkspaceLocalRepository.InboxNotificationPreferencesRecord {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT grouping, sort_order, bell_enabled, global_content_mode,
                           global_row_state_filter, pane_content_mode, pane_row_state_filter
                    FROM local_inbox_notification_preferences
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            ),
            let grouping = InboxNotificationGrouping(rawValue: row["grouping"]),
            let sortOrder = InboxNotificationSort(rawValue: row["sort_order"]),
            let globalContentMode = InboxNotificationContentMode(rawValue: row["global_content_mode"]),
            let globalRowStateFilter = InboxNotificationRowStateFilter(rawValue: row["global_row_state_filter"]),
            let paneContentMode = InboxNotificationContentMode(rawValue: row["pane_content_mode"]),
            let paneRowStateFilter = InboxNotificationRowStateFilter(rawValue: row["pane_row_state_filter"])
        else {
            return .default
        }
        return .init(
            grouping: grouping,
            sortOrder: sortOrder,
            bellEnabled: (row["bell_enabled"] as Int) == 1,
            globalContentMode: globalContentMode,
            globalRowStateFilter: globalRowStateFilter,
            paneContentMode: paneContentMode,
            paneRowStateFilter: paneRowStateFilter
        )
    }

    private static func ensureMainWindowRow(_ database: Database, updatedAt: Date) throws -> String {
        if let existingWindowId = try String.fetchOne(
            database,
            sql: "SELECT window_id FROM local_window_state WHERE window_role = 'main'"
        ) {
            return existingWindowId
        }
        let windowId = UUIDv7.generate().uuidString
        try database.execute(
            sql: """
                INSERT INTO local_window_state(
                    window_id, window_role, sidebar_width, window_frame_json, filter_text,
                    is_filter_visible, sidebar_collapsed, sidebar_surface, updated_at
                ) VALUES (?, 'main', 250, NULL, '', 0, 0, ?, ?)
                """,
            arguments: [
                windowId,
                SQLiteLocalUXStorage.storageValue(for: SidebarSurface.repos),
                updatedAt.timeIntervalSince1970,
            ]
        )
        return windowId
    }

    private static func resetWindowPresentation(_ database: Database, updatedAt: Date) throws {
        guard
            let windowId = try String.fetchOne(
                database,
                sql: "SELECT window_id FROM local_window_state WHERE window_role = 'main'"
            )
        else {
            return
        }
        try database.execute(
            sql: """
                UPDATE local_window_state
                SET sidebar_width = 250, window_frame_json = NULL, updated_at = ?
                WHERE window_id = ?
                """,
            arguments: [updatedAt.timeIntervalSince1970, windowId]
        )
    }

    private static func mainWindowExists(_ database: Database) throws -> Bool {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM local_window_state WHERE window_role = 'main'"
        ) == 1
    }

    private static func workspaceRowExists(
        _ database: Database,
        table: String,
        workspaceId: UUID
    ) throws -> Bool {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM \(table) WHERE workspace_id = ? LIMIT 1",
            arguments: [workspaceId.uuidString]
        ) ?? 0 > 0
    }

    private static func deleteWorkspaceRows(
        _ database: Database,
        table: String,
        workspaceIdString: String
    ) throws {
        try database.execute(
            sql: "DELETE FROM \(table) WHERE workspace_id = ?",
            arguments: [workspaceIdString]
        )
    }

    private static func activeArrangementIdsByTabId(from rows: [Row]) throws -> [UUID: UUID] {
        try Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let arrangementIdString: String = row["active_arrangement_id"] else { return nil }
                return (
                    try WorkspaceLocalRepositoryCodecs.uuid(
                        row["tab_id"],
                        WorkspaceLocalRepositoryError.malformedTabId
                    ),
                    try WorkspaceLocalRepositoryCodecs.uuid(
                        arrangementIdString,
                        WorkspaceLocalRepositoryError.malformedArrangementId
                    )
                )
            }
        )
    }

    private static func activePaneIdsByArrangementId(from rows: [Row]) throws -> [UUID: UUID] {
        try Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let paneIdString: String = row["active_pane_id"] else { return nil }
                return (
                    try WorkspaceLocalRepositoryCodecs.uuid(
                        row["arrangement_id"],
                        WorkspaceLocalRepositoryError.malformedArrangementId
                    ),
                    try WorkspaceLocalRepositoryCodecs.uuid(
                        paneIdString,
                        WorkspaceLocalRepositoryError.malformedPaneId
                    )
                )
            }
        )
    }

    private static func drawerExpansionByDrawerId(from rows: [Row]) throws -> [UUID: Bool] {
        try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                (
                    try WorkspaceLocalRepositoryCodecs.uuid(
                        row["drawer_id"],
                        WorkspaceLocalRepositoryError.malformedDrawerId
                    ),
                    (row["is_expanded"] as Int) == 1
                )
            }
        )
    }

    private static func activeChildIdsByArrangementDrawer(
        from rows: [Row]
    ) throws -> [WorkspaceLocalRepository.ArrangementDrawerCursorKey: UUID] {
        try Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let activeChildIdString: String = row["active_child_id"] else { return nil }
                let key = WorkspaceLocalRepository.ArrangementDrawerCursorKey(
                    arrangementId: try WorkspaceLocalRepositoryCodecs.uuid(
                        row["arrangement_id"],
                        WorkspaceLocalRepositoryError.malformedArrangementId
                    ),
                    drawerId: try WorkspaceLocalRepositoryCodecs.uuid(
                        row["drawer_id"],
                        WorkspaceLocalRepositoryError.malformedDrawerId
                    )
                )
                return (
                    key,
                    try WorkspaceLocalRepositoryCodecs.uuid(
                        activeChildIdString,
                        WorkspaceLocalRepositoryError.malformedPaneId
                    )
                )
            }
        )
    }
}
