import GRDB

enum WorkspaceLocalMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        for migration in migrations {
            migrator.registerMigration(migration.identifier) { database in
                try execute(migration.statements, on: database)
            }
        }
        return migrator
    }

    static func migrate(_ writer: any DatabaseWriter) throws {
        try migrator.migrate(writer)
    }

    private static let migrations: [(identifier: String, statements: [String])] = [
        ("001_create_local_cursors", createLocalCursorStatements),
        ("002_create_local_workspace_memory", createLocalWorkspaceMemoryStatements),
        ("003_create_local_notifications", createLocalNotificationStatements),
        ("004_create_cache_tables", createCacheTableStatements),
        ("005_enforce_notification_claim_keys", enforceNotificationClaimKeyStatements),
        ("006_create_local_persistence_lane_markers", createLocalPersistenceLaneMarkerStatements),
        ("007_create_local_workspace_sqlite_snapshot_status", createLocalWorkspaceSQLiteSnapshotStatusStatements),
    ]

    private static func execute(_ statements: [String], on database: Database) throws {
        for statement in statements {
            try database.execute(sql: statement)
        }
    }

    private static let createLocalCursorStatements = [
        """
        CREATE TABLE local_workspace_cursor (
            workspace_id TEXT PRIMARY KEY,
            active_tab_id TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_tab_cursor (
            tab_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            active_arrangement_id TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_arrangement_cursor (
            arrangement_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            active_pane_id TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_drawer_cursor (
            drawer_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            is_expanded INTEGER NOT NULL CHECK (is_expanded IN (0, 1)),
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_arrangement_drawer_cursor (
            arrangement_id TEXT NOT NULL,
            drawer_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            active_child_id TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY(arrangement_id, drawer_id)
        )
        """,
        """
        CREATE INDEX idx_local_tab_cursor_workspace_id
        ON local_tab_cursor(workspace_id)
        """,
        """
        CREATE INDEX idx_local_arrangement_cursor_workspace_id
        ON local_arrangement_cursor(workspace_id)
        """,
        """
        CREATE INDEX idx_local_drawer_cursor_workspace_id
        ON local_drawer_cursor(workspace_id)
        """,
        """
        CREATE UNIQUE INDEX idx_local_drawer_cursor_one_expanded_per_workspace
        ON local_drawer_cursor(workspace_id)
        WHERE is_expanded = 1
        """,
        """
        CREATE INDEX idx_local_arrangement_drawer_cursor_workspace_id
        ON local_arrangement_drawer_cursor(workspace_id)
        """,
        """
        CREATE INDEX idx_local_arrangement_drawer_cursor_drawer_id
        ON local_arrangement_drawer_cursor(workspace_id, drawer_id)
        """,
    ]

    private static let createLocalWorkspaceMemoryStatements = [
        """
        CREATE TABLE local_workspace_window_state (
            workspace_id TEXT PRIMARY KEY,
            sidebar_width REAL NOT NULL,
            window_frame_json TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_sidebar_state (
            workspace_id TEXT PRIMARY KEY,
            filter_text TEXT NOT NULL,
            is_filter_visible INTEGER NOT NULL CHECK (is_filter_visible IN (0, 1)),
            sidebar_collapsed INTEGER NOT NULL CHECK (sidebar_collapsed IN (0, 1)),
            sidebar_surface TEXT NOT NULL CHECK (
                sidebar_surface IN (\(SQLiteLocalUXStorage.sidebarSurfaceSQLValues)
                )
            ),
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_sidebar_expanded_group (
            workspace_id TEXT NOT NULL,
            group_key TEXT NOT NULL,
            PRIMARY KEY(workspace_id, group_key)
        )
        """,
        """
        CREATE TABLE local_recent_workspace_target (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            path TEXT NOT NULL,
            display_title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            repo_id TEXT,
            worktree_id TEXT,
            kind TEXT NOT NULL CHECK (
                kind IN (\(SQLiteLocalUXStorage.recentWorkspaceTargetKindSQLValues)
                )
            ),
            last_opened_at REAL NOT NULL,
            CHECK (
                (
                    kind = '\(SQLiteLocalUXStorage.recentWorkspaceTargetKindWorktree)'
                    AND repo_id IS NOT NULL
                    AND worktree_id IS NOT NULL
                )
                    OR (
                        kind = '\(SQLiteLocalUXStorage.recentWorkspaceTargetKindCwdOnly)'
                        AND repo_id IS NULL
                        AND worktree_id IS NULL
                    )
            )
        )
        """,
        """
        CREATE INDEX idx_local_recent_workspace_target_workspace_id
        ON local_recent_workspace_target(workspace_id, last_opened_at)
        """,
    ]

    private static let notificationInboxItem005Columns = """
        id,
        workspace_id,
        timestamp,
        kind,
        title,
        body,
        source_kind,
        pane_id,
        tab_id,
        tab_display_label,
        tab_ordinal,
        repo_id,
        repo_name,
        worktree_id,
        worktree_name,
        branch_name,
        pane_display_label,
        pane_ordinal,
        pane_role,
        parent_pane_id,
        parent_pane_display_label,
        parent_pane_ordinal,
        drawer_ordinal,
        runtime_display_label,
        activity_burst_window_id,
        activity_session_id,
        activity_event_count,
        activity_rows_added,
        activity_threshold_rows,
        activity_latest_rows,
        claim_pane_id,
        claim_lane,
        claim_semantic,
        claim_session_id,
        is_read,
        is_dismissed_from_pane_inbox
        """

    private static let notificationClaimLane003MergeableSQLValues = "'activity', 'actionNeeded'"
    private static let notificationClaimLane005AllSQLValues = "'activity', 'actionNeeded', 'safety'"
    private static let notificationClaimLane005MergeableSQLValues = "'activity', 'actionNeeded'"

    private static let notificationClaimKey005ValidPredicate = """
        claim_pane_id IS NOT NULL
            AND claim_lane IS NOT NULL
            AND claim_lane IN (\(notificationClaimLane005AllSQLValues))
            AND claim_semantic IS NOT NULL
        """

    private static let createLocalNotificationStatements =
        [
            """
            CREATE TABLE local_notification_inbox_collapsed_group (
                workspace_id TEXT NOT NULL,
                group_key TEXT NOT NULL,
                PRIMARY KEY(workspace_id, group_key)
            )
            """,
            notificationInboxItem003CreateStatement,
        ] + notificationInboxItem003IndexStatements

    private static var enforceNotificationClaimKeyStatements: [String] {
        [
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_claim_session
            """,
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_claim_exact
            """,
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_worktree_id
            """,
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_repo_id
            """,
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_tab_id
            """,
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_pane_id
            """,
            """
            DROP INDEX IF EXISTS idx_local_notification_inbox_item_workspace_timestamp
            """,
            notificationInboxItem005CreateRebuildStatement,
            """
            INSERT INTO local_notification_inbox_item_rebuild (
                \(notificationInboxItem005Columns)
            )
            SELECT
                id,
                workspace_id,
                timestamp,
                kind,
                title,
                body,
                source_kind,
                pane_id,
                tab_id,
                tab_display_label,
                tab_ordinal,
                repo_id,
                repo_name,
                worktree_id,
                worktree_name,
                branch_name,
                pane_display_label,
                pane_ordinal,
                pane_role,
                parent_pane_id,
                parent_pane_display_label,
                parent_pane_ordinal,
                drawer_ordinal,
                runtime_display_label,
                activity_burst_window_id,
                activity_session_id,
                activity_event_count,
                activity_rows_added,
                activity_threshold_rows,
                activity_latest_rows,
                CASE WHEN \(notificationClaimKey005ValidPredicate) THEN claim_pane_id ELSE NULL END,
                CASE WHEN \(notificationClaimKey005ValidPredicate) THEN claim_lane ELSE NULL END,
                CASE WHEN \(notificationClaimKey005ValidPredicate) THEN claim_semantic ELSE NULL END,
                CASE WHEN \(notificationClaimKey005ValidPredicate) THEN claim_session_id ELSE NULL END,
                is_read,
                is_dismissed_from_pane_inbox
            FROM local_notification_inbox_item
            """,
            """
            DROP TABLE local_notification_inbox_item
            """,
            """
            ALTER TABLE local_notification_inbox_item_rebuild
            RENAME TO local_notification_inbox_item
            """,
        ] + notificationInboxItem005IndexStatements
    }

    private static let notificationInboxItem003CreateStatement = """
        CREATE TABLE local_notification_inbox_item (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT,
            source_kind TEXT NOT NULL,
            pane_id TEXT,
            tab_id TEXT,
            tab_display_label TEXT,
            tab_ordinal INTEGER,
            repo_id TEXT,
            repo_name TEXT,
            worktree_id TEXT,
            worktree_name TEXT,
            branch_name TEXT,
            pane_display_label TEXT,
            pane_ordinal INTEGER,
            pane_role TEXT,
            parent_pane_id TEXT,
            parent_pane_display_label TEXT,
            parent_pane_ordinal INTEGER,
            drawer_ordinal INTEGER,
            runtime_display_label TEXT,
            activity_burst_window_id TEXT,
            activity_session_id TEXT,
            activity_event_count INTEGER,
            activity_rows_added INTEGER,
            activity_threshold_rows INTEGER,
            activity_latest_rows INTEGER,
            claim_pane_id TEXT,
            claim_lane TEXT,
            claim_semantic TEXT,
            claim_session_id TEXT,
            is_read INTEGER NOT NULL CHECK (is_read IN (0, 1)),
            is_dismissed_from_pane_inbox INTEGER NOT NULL CHECK (is_dismissed_from_pane_inbox IN (0, 1))
        )
        """

    private static let notificationInboxItem005CreateRebuildStatement = """
        CREATE TABLE local_notification_inbox_item_rebuild (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT,
            source_kind TEXT NOT NULL,
            pane_id TEXT,
            tab_id TEXT,
            tab_display_label TEXT,
            tab_ordinal INTEGER,
            repo_id TEXT,
            repo_name TEXT,
            worktree_id TEXT,
            worktree_name TEXT,
            branch_name TEXT,
            pane_display_label TEXT,
            pane_ordinal INTEGER,
            pane_role TEXT,
            parent_pane_id TEXT,
            parent_pane_display_label TEXT,
            parent_pane_ordinal INTEGER,
            drawer_ordinal INTEGER,
            runtime_display_label TEXT,
            activity_burst_window_id TEXT,
            activity_session_id TEXT,
            activity_event_count INTEGER,
            activity_rows_added INTEGER,
            activity_threshold_rows INTEGER,
            activity_latest_rows INTEGER,
            claim_pane_id TEXT,
            claim_lane TEXT,
            claim_semantic TEXT,
            claim_session_id TEXT,
            is_read INTEGER NOT NULL CHECK (is_read IN (0, 1)),
            is_dismissed_from_pane_inbox INTEGER NOT NULL CHECK (is_dismissed_from_pane_inbox IN (0, 1)),
            CHECK (
                (
                    claim_pane_id IS NULL
                    AND claim_lane IS NULL
                    AND claim_semantic IS NULL
                    AND claim_session_id IS NULL
                )
                OR (
                    \(notificationClaimKey005ValidPredicate)
                )
            )
        )
        """

    private static let notificationInboxItem003IndexStatements = [
        """
        CREATE INDEX idx_local_notification_inbox_item_workspace_timestamp
        ON local_notification_inbox_item(workspace_id, timestamp)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_pane_id
        ON local_notification_inbox_item(workspace_id, pane_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_tab_id
        ON local_notification_inbox_item(workspace_id, tab_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_repo_id
        ON local_notification_inbox_item(workspace_id, repo_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_worktree_id
        ON local_notification_inbox_item(workspace_id, worktree_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_claim_exact
        ON local_notification_inbox_item(
            workspace_id,
            claim_pane_id,
            claim_lane,
            claim_semantic,
            claim_session_id
        )
        WHERE claim_pane_id IS NOT NULL
            AND claim_lane IS NOT NULL
            AND claim_semantic IS NOT NULL
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_claim_session
        ON local_notification_inbox_item(
            workspace_id,
            claim_pane_id,
            claim_session_id
        )
        WHERE claim_pane_id IS NOT NULL
            AND claim_session_id IS NOT NULL
            AND claim_lane IN (\(notificationClaimLane003MergeableSQLValues))
        """,
    ]

    private static let notificationInboxItem005IndexStatements = [
        """
        CREATE INDEX idx_local_notification_inbox_item_workspace_timestamp
        ON local_notification_inbox_item(workspace_id, timestamp)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_pane_id
        ON local_notification_inbox_item(workspace_id, pane_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_tab_id
        ON local_notification_inbox_item(workspace_id, tab_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_repo_id
        ON local_notification_inbox_item(workspace_id, repo_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_worktree_id
        ON local_notification_inbox_item(workspace_id, worktree_id)
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_claim_exact
        ON local_notification_inbox_item(
            workspace_id,
            claim_pane_id,
            claim_lane,
            claim_semantic,
            claim_session_id
        )
        WHERE claim_pane_id IS NOT NULL
            AND claim_lane IS NOT NULL
            AND claim_semantic IS NOT NULL
        """,
        """
        CREATE INDEX idx_local_notification_inbox_item_claim_session
        ON local_notification_inbox_item(
            workspace_id,
            claim_pane_id,
            claim_session_id
        )
        WHERE claim_pane_id IS NOT NULL
            AND claim_session_id IS NOT NULL
            AND claim_lane IN (\(notificationClaimLane005MergeableSQLValues))
        """,
    ]

    private static let createCacheTableStatements = [
        """
        CREATE TABLE cache_metadata (
            workspace_id TEXT PRIMARY KEY,
            source_revision INTEGER NOT NULL DEFAULT 0 CHECK (source_revision >= 0),
            last_rebuilt_at REAL
        )
        """,
        """
        CREATE TABLE cache_repo_enrichment (
            repo_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            state TEXT NOT NULL,
            origin TEXT,
            upstream TEXT,
            group_key TEXT,
            remote_slug TEXT,
            organization_name TEXT,
            display_name TEXT,
            updated_at REAL NOT NULL,
            payload_json TEXT
        )
        """,
        """
        CREATE TABLE cache_worktree_enrichment (
            worktree_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            repo_id TEXT NOT NULL,
            branch TEXT,
            is_main_worktree INTEGER NOT NULL CHECK (is_main_worktree IN (0, 1)),
            updated_at REAL NOT NULL,
            payload_json TEXT
        )
        """,
        """
        CREATE TABLE cache_pull_request_count (
            worktree_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            repo_id TEXT,
            count INTEGER NOT NULL CHECK (count >= 0),
            updated_at REAL NOT NULL
        )
        """,
        // cache_notification_count is retained for migration compatibility only.
        // Unread notification counts are owned by InboxNotificationAtom and its feature store.
        """
        CREATE TABLE cache_notification_count (
            worktree_id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            repo_id TEXT,
            count INTEGER NOT NULL CHECK (count >= 0),
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE INDEX idx_cache_repo_enrichment_workspace_id
        ON cache_repo_enrichment(workspace_id)
        """,
        """
        CREATE INDEX idx_cache_worktree_enrichment_workspace_id
        ON cache_worktree_enrichment(workspace_id)
        """,
        """
        CREATE INDEX idx_cache_worktree_enrichment_repo_id
        ON cache_worktree_enrichment(repo_id)
        """,
        """
        CREATE INDEX idx_cache_pull_request_count_workspace_id
        ON cache_pull_request_count(workspace_id)
        """,
        """
        CREATE INDEX idx_cache_pull_request_count_repo_id
        ON cache_pull_request_count(workspace_id, repo_id)
        """,
        """
        CREATE INDEX idx_cache_notification_count_workspace_id
        ON cache_notification_count(workspace_id)
        """,
        """
        CREATE INDEX idx_cache_notification_count_repo_id
        ON cache_notification_count(workspace_id, repo_id)
        """,
    ]

    private static let createLocalPersistenceLaneMarkerStatements = [
        """
        CREATE TABLE local_persistence_lane_marker (
            workspace_id TEXT NOT NULL,
            lane TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(workspace_id, lane)
        )
        """,
        """
        CREATE INDEX idx_local_persistence_lane_marker_workspace_id
        ON local_persistence_lane_marker(workspace_id)
        """,
    ]

    private static let createLocalWorkspaceSQLiteSnapshotStatusStatements = [
        """
        CREATE TABLE local_workspace_sqlite_snapshot_status (
            workspace_id TEXT PRIMARY KEY,
            completed_at REAL NOT NULL
        )
        """,
        """
        INSERT INTO local_workspace_sqlite_snapshot_status(workspace_id, completed_at)
        SELECT workspace_id, updated_at
        FROM local_workspace_cursor
        """,
    ]
}
