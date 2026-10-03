import GRDB

extension WorkspaceLocalMigrations {
    static func registerCLIReportCursor(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("018_create_sessions_cli_report_cursor") { database in
            try database.execute(
                sql: """
                    CREATE TABLE sessions_cli_report_cursor (
                        store_id TEXT PRIMARY KEY NOT NULL,
                        last_handled_sequence INTEGER NOT NULL
                    )
                    """)
        }
    }
}
