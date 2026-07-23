import GRDB

enum WorkspaceLocalMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("001_create_application_local_schema") { database in
            for statement in createApplicationLocalSchemaStatements {
                try database.execute(sql: statement)
            }
        }
        return migrator
    }

    static func migrate(_ writer: any DatabaseWriter) throws {
        try migrator.migrate(writer)
    }

    private static let createApplicationLocalSchemaStatements = [
        """
        CREATE TABLE local_workspace_cursor (
            workspace_id TEXT PRIMARY KEY,
            active_tab_id TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_tab_cursor (
            workspace_id TEXT NOT NULL,
            tab_id TEXT NOT NULL,
            active_arrangement_id TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY (workspace_id, tab_id)
        )
        """,
        "CREATE INDEX idx_local_tab_cursor_workspace ON local_tab_cursor(workspace_id)",
        """
        CREATE TABLE local_arrangement_cursor (
            workspace_id TEXT NOT NULL,
            arrangement_id TEXT NOT NULL,
            active_pane_id TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY (workspace_id, arrangement_id)
        )
        """,
        "CREATE INDEX idx_local_arrangement_cursor_workspace ON local_arrangement_cursor(workspace_id)",
        """
        CREATE TABLE local_drawer_cursor (
            workspace_id TEXT NOT NULL,
            drawer_id TEXT NOT NULL,
            is_expanded INTEGER NOT NULL CHECK (is_expanded IN (0, 1)),
            updated_at REAL NOT NULL,
            PRIMARY KEY (workspace_id, drawer_id)
        )
        """,
        "CREATE INDEX idx_local_drawer_cursor_workspace ON local_drawer_cursor(workspace_id)",
        """
        CREATE UNIQUE INDEX idx_local_drawer_one_expanded_per_workspace
        ON local_drawer_cursor(workspace_id)
        WHERE is_expanded = 1
        """,
        """
        CREATE TABLE local_arrangement_drawer_cursor (
            workspace_id TEXT NOT NULL,
            arrangement_id TEXT NOT NULL,
            drawer_id TEXT NOT NULL,
            active_child_id TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY (workspace_id, arrangement_id, drawer_id)
        )
        """,
        """
        CREATE INDEX idx_local_arrangement_drawer_cursor_workspace
        ON local_arrangement_drawer_cursor(workspace_id)
        """,
        """
        CREATE TABLE local_window_state (
            window_id TEXT PRIMARY KEY,
            window_role TEXT NOT NULL UNIQUE CHECK (window_role = 'main'),
            sidebar_width REAL NOT NULL,
            window_frame_json TEXT,
            filter_text TEXT NOT NULL,
            is_filter_visible INTEGER NOT NULL CHECK (is_filter_visible IN (0, 1)),
            sidebar_collapsed INTEGER NOT NULL CHECK (sidebar_collapsed IN (0, 1)),
            sidebar_surface TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_window_sidebar_expanded_group (
            window_id TEXT NOT NULL REFERENCES local_window_state(window_id) ON DELETE CASCADE,
            group_key TEXT NOT NULL,
            PRIMARY KEY (window_id, group_key)
        )
        """,
        """
        CREATE TABLE local_recent_workspace_target (
            workspace_id TEXT NOT NULL,
            id TEXT NOT NULL,
            path TEXT NOT NULL,
            display_title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            repo_id TEXT,
            worktree_id TEXT,
            kind TEXT NOT NULL,
            last_opened_at REAL NOT NULL,
            PRIMARY KEY (workspace_id, id)
        )
        """,
        """
        CREATE INDEX idx_local_recent_target_workspace_time
        ON local_recent_workspace_target(workspace_id, last_opened_at)
        """,
        """
        CREATE TABLE local_notification_inbox_collapsed_group (
            workspace_id TEXT NOT NULL,
            group_key TEXT NOT NULL,
            PRIMARY KEY (workspace_id, group_key)
        )
        """,
        """
        CREATE TABLE local_notification_inbox_item (
            workspace_id TEXT NOT NULL,
            id TEXT NOT NULL,
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
            PRIMARY KEY (workspace_id, id)
        )
        """,
        """
        CREATE INDEX idx_notification_workspace_timestamp
        ON local_notification_inbox_item(workspace_id, timestamp)
        """,
        """
        CREATE INDEX idx_notification_workspace_pane
        ON local_notification_inbox_item(workspace_id, pane_id)
        """,
        """
        CREATE INDEX idx_notification_workspace_tab
        ON local_notification_inbox_item(workspace_id, tab_id)
        """,
        """
        CREATE INDEX idx_notification_workspace_repo
        ON local_notification_inbox_item(workspace_id, repo_id)
        """,
        """
        CREATE INDEX idx_notification_workspace_worktree
        ON local_notification_inbox_item(workspace_id, worktree_id)
        """,
        """
        CREATE INDEX idx_notification_claim_exact
        ON local_notification_inbox_item(
            workspace_id, claim_pane_id, claim_lane, claim_semantic, claim_session_id
        )
        WHERE claim_pane_id IS NOT NULL
          AND claim_lane IS NOT NULL
          AND claim_semantic IS NOT NULL
        """,
        """
        CREATE INDEX idx_notification_claim_session
        ON local_notification_inbox_item(workspace_id, claim_pane_id, claim_session_id)
        WHERE claim_pane_id IS NOT NULL
          AND claim_session_id IS NOT NULL
        """,
        """
        CREATE TABLE local_editor_preferences (
            workspace_id TEXT PRIMARY KEY,
            bookmarked_editor_id TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_repo_explorer_preferences (
            workspace_id TEXT PRIMARY KEY,
            grouping_mode TEXT NOT NULL,
            sort_order TEXT NOT NULL,
            visibility_mode TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE local_inbox_notification_preferences (
            workspace_id TEXT PRIMARY KEY,
            grouping TEXT NOT NULL,
            sort_order TEXT NOT NULL,
            bell_enabled INTEGER NOT NULL CHECK (bell_enabled IN (0, 1)),
            global_content_mode TEXT NOT NULL,
            global_row_state_filter TEXT NOT NULL,
            pane_content_mode TEXT NOT NULL,
            pane_row_state_filter TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE cache_metadata (
            singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
            source_revision INTEGER NOT NULL DEFAULT 0 CHECK (source_revision >= 0),
            last_rebuilt_at REAL
        )
        """,
        """
        CREATE TABLE cache_repo_enrichment (
            repo_id TEXT PRIMARY KEY,
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
            repo_id TEXT NOT NULL,
            branch TEXT,
            is_main_worktree INTEGER NOT NULL CHECK (is_main_worktree IN (0, 1)),
            updated_at REAL NOT NULL,
            payload_json TEXT
        )
        """,
        "CREATE INDEX idx_cache_worktree_repo ON cache_worktree_enrichment(repo_id)",
        """
        CREATE TABLE cache_pull_request_count (
            worktree_id TEXT PRIMARY KEY,
            repo_id TEXT,
            count INTEGER NOT NULL CHECK (count >= 0),
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX idx_cache_pull_request_repo ON cache_pull_request_count(repo_id)",
    ]
}
