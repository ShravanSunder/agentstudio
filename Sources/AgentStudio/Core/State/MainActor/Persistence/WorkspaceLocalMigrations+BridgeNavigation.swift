import GRDB

extension WorkspaceLocalMigrations {
    /// Receiver navigation memory is local UX memory keyed by workspace and
    /// receiving pane. It is boot-required because hydration installs it
    /// before any Bridge mounts.
    static func registerBridgeNavigationSchema(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("016_create_bridge_navigation_schema") { database in
            try database.execute(
                sql: """
                    CREATE TABLE local_bridge_navigation (
                        workspace_id TEXT NOT NULL,
                        receiver_pane_id TEXT NOT NULL,
                        receiver_kind TEXT NOT NULL,
                        payload_version INTEGER NOT NULL,
                        payload_json TEXT NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (workspace_id, receiver_pane_id)
                    )
                    """
            )
        }
    }
}
