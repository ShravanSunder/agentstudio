import GRDB

extension WorkspaceCoreMigrations {
    private static let dropPaneSourceBindingMigrationIdentifier = "009_drop_pane_source_binding"

    static func isDropPaneSourceBindingMigrationPending(_ database: Database) throws -> Bool {
        let completedMigrations = try migrator.completedMigrations(database)
        guard !completedMigrations.contains(dropPaneSourceBindingMigrationIdentifier) else {
            return false
        }

        let paneTableExists =
            try Bool.fetchOne(
                database,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM sqlite_master
                        WHERE type = 'table' AND name = 'pane'
                    )
                    """
            ) ?? false
        guard paneTableExists else { return false }

        let paneColumnNames = try Set(
            Row.fetchAll(database, sql: "PRAGMA table_info(pane)")
                .map { row in row["name"] as String }
        )
        return paneColumnNames.contains("source_kind")
            && !paneColumnNames.contains("facet_repo_id")
    }
}
