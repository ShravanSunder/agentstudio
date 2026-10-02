import GRDB

extension WorkspaceLocalMigrations {
    static func registerCLIReportCursor(in migrator: inout DatabaseMigrator) {
        // S4 RED stand-in: the cursor schema frontier is declared, not implemented.
        migrator.registerMigration("018_create_sessions_cli_report_cursor") { _ in }
    }
}
