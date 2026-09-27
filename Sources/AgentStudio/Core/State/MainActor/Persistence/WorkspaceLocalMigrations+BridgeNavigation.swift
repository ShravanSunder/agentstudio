import GRDB

extension WorkspaceLocalMigrations {
    /// #367's unshipped receiver schema is amended in place. Values and
    /// contributions have different write patterns and never use JSON rows.
    static func registerBridgeNavigationSchema(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("016_create_bridge_navigation_schema") { database in
            try database.execute(
                sql: """
                    CREATE TABLE bridge_receiver_state (
                        workspace_id TEXT NOT NULL,
                        receiver_pane_id TEXT NOT NULL,
                        receiver_kind TEXT NOT NULL,
                        kind TEXT NOT NULL,
                        item_key TEXT NOT NULL,
                        generation INTEGER NOT NULL,
                        is_deleted INTEGER NOT NULL CHECK (is_deleted IN (0, 1)),
                        text_value TEXT,
                        worktree_id TEXT,
                        forge_host TEXT,
                        forge_owner TEXT,
                        forge_repository TEXT,
                        forge_number INTEGER,
                        document_path TEXT,
                        provenance_repo_id TEXT,
                        provenance_worktree_id TEXT,
                        provenance_relative_path TEXT,
                        comparison_kind TEXT,
                        comparison_basis TEXT,
                        comparison_name TEXT,
                        comparison_branch TEXT,
                        comparison_remote TEXT,
                        comparison_oid TEXT,
                        ordinal INTEGER,
                        imported_variant TEXT,
                        imported_payload TEXT,
                        PRIMARY KEY (workspace_id, receiver_pane_id, kind, item_key)
                    )
                    """
            )
            try database.execute(
                sql: """
                    CREATE TABLE bridge_receiver_item (
                        workspace_id TEXT NOT NULL,
                        receiver_pane_id TEXT NOT NULL,
                        receiver_kind TEXT NOT NULL,
                        kind TEXT NOT NULL,
                        item_key TEXT NOT NULL,
                        contributor_key TEXT NOT NULL,
                        generation INTEGER NOT NULL,
                        is_deleted INTEGER NOT NULL CHECK (is_deleted IN (0, 1)),
                        worktree_id TEXT,
                        forge_host TEXT,
                        forge_owner TEXT,
                        forge_repository TEXT,
                        forge_number INTEGER,
                        contributor_kind TEXT,
                        contributor_provider TEXT,
                        contributor_session_ref TEXT,
                        added_at REAL,
                        PRIMARY KEY (workspace_id, receiver_pane_id, kind, item_key, contributor_key)
                    )
                    """
            )
            try database.execute(
                sql: """
                    CREATE TABLE bridge_receiver_retirement (
                        workspace_id TEXT NOT NULL,
                        receiver_pane_id TEXT NOT NULL,
                        retired_at REAL NOT NULL,
                        purge_after REAL NOT NULL,
                        PRIMARY KEY (workspace_id, receiver_pane_id)
                    )
                    """
            )
        }
    }
}
