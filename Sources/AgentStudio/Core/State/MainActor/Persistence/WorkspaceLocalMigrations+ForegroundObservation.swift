import GRDB

extension WorkspaceLocalMigrations {
    static func registerPaneForegroundObservation(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("017_create_terminal_pane_foreground_observation") { database in
            try database.execute(
                sql: """
                    CREATE TABLE terminal_pane_foreground_observation (
                        pane_id TEXT PRIMARY KEY,
                        zmx_session_id TEXT NOT NULL,
                        binding_generation_id TEXT,
                        program TEXT NOT NULL,
                        observer_launch_id TEXT NOT NULL,
                        sequence INTEGER NOT NULL CHECK (sequence >= 0),
                        observed_at TEXT NOT NULL,
                        identity_version INTEGER NOT NULL,
                        boot_id TEXT NOT NULL,
                        daemon_pid INTEGER NOT NULL,
                        daemon_start_seconds INTEGER NOT NULL,
                        daemon_start_microseconds INTEGER NOT NULL,
                        leader_pid INTEGER NOT NULL,
                        leader_start_seconds INTEGER NOT NULL,
                        leader_start_microseconds INTEGER NOT NULL,
                        process_group_id INTEGER NOT NULL,
                        session_created_at INTEGER NOT NULL
                    )
                    """)
        }
    }
}
