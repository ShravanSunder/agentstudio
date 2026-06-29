import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryMetadataMigrationTests")
struct WorkspaceCoreRepositoryMetadataMigrationTests {
    @Test("migration 010 creates repo tags, adds tab color, and drops pane tags")
    func migration010CreatesRepoTagsAddsTabColorAndDropsPaneTags() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceCoreMigrations.migrator.migrate(databaseQueue, upTo: "009_drop_pane_source_binding")
        let tableNamesBeforeMigration = try tableNames(in: databaseQueue)
        let tabShellColumnsBeforeMigration = try columnNames(in: databaseQueue, tableName: "tab_shell")
        #expect(!tableNamesBeforeMigration.contains("repo_tag"))
        #expect(!tableNamesBeforeMigration.contains("worktree_tag"))
        #expect(!tabShellColumnsBeforeMigration.contains("color_hex"))
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE IF NOT EXISTS pane_tag (
                        pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
                        tag TEXT NOT NULL,
                        PRIMARY KEY(pane_id, tag)
                    )
                    """
            )
        }

        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "010_repository_topology_tags_and_tab_color"
        )

        let tableNamesAfterMigration = try tableNames(in: databaseQueue)
        let tabShellColumns = try columnNames(in: databaseQueue, tableName: "tab_shell")

        #expect(!tableNamesAfterMigration.contains("pane_tag"))
        #expect(tableNamesAfterMigration.contains("repo_tag"))
        #expect(!tableNamesAfterMigration.contains("worktree_tag"))
        #expect(tabShellColumns.contains("color_hex"))
    }

    @Test("migration 011 adds repo sidebar metadata")
    func migration011AddsRepoSidebarMetadata() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "010_repository_topology_tags_and_tab_color"
        )

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let repoColumns = try columnNames(in: databaseQueue, tableName: "repo")
        let worktreeColumns = try columnNames(in: databaseQueue, tableName: "worktree")
        #expect(repoColumns.contains("is_favorite"))
        #expect(repoColumns.contains("note"))
        #expect(worktreeColumns.contains("note"))
    }
}

private func tableNames(in databaseQueue: DatabaseQueue) throws -> [String] {
    try databaseQueue.read { database in
        try String.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                ORDER BY name
                """
        )
    }
}

private func columnNames(in databaseQueue: DatabaseQueue, tableName: String) throws -> [String] {
    try databaseQueue.read { database in
        try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
            .map { row in row["name"] as String }
    }
}
