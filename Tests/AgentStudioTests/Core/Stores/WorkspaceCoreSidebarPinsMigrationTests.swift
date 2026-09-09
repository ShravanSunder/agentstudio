import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Workspace core sidebar pins migration")
struct WorkspaceCoreSidebarPinsMigrationTests {
    @Test("migration 017 preserves repository pins and defaults existing panes to unpinned")
    func migration017PreservesRepositoryPinsAndDefaultsExistingPanesToUnpinned() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.migration-017.sidebar-pins"
        )
        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "016_add_pane_association_facets"
        )
        let workspaceId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace(id, name, created_at, updated_at)
                    VALUES (?, 'Sidebar pins', 1, 1)
                    """,
                arguments: [workspaceId.uuidString]
            )
            try database.execute(
                sql: """
                    INSERT INTO repo(id, name, repo_path, stable_key, created_at, is_favorite)
                    VALUES (?, 'repo', '/tmp/sidebar-pins', 'sidebar-pins', 1, 1)
                    """,
                arguments: [repoId.uuidString]
            )
            try database.execute(
                sql: """
                    INSERT INTO pane(
                        id, workspace_id, content_type, execution_backend,
                        title, residency_kind, kind, created_at, updated_at
                    ) VALUES (?, ?, ?, 'local', 'Terminal', 'active', 'leaf', 1, 1)
                    """,
                arguments: [
                    paneId.uuidString,
                    workspaceId.uuidString,
                    SQLitePaneContentTypeStorage.storageValue(for: .terminal),
                ]
            )
        }

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let migrated = try databaseQueue.read { database in
            let repoColumns = try Set(String.fetchAll(database, sql: "SELECT name FROM pragma_table_info('repo')"))
            let paneColumns = try Set(String.fetchAll(database, sql: "SELECT name FROM pragma_table_info('pane')"))
            let repoPinned = try Int.fetchOne(
                database,
                sql: "SELECT is_pinned FROM repo WHERE id = ?",
                arguments: [repoId.uuidString]
            )
            let panePinned = try Int.fetchOne(
                database,
                sql: "SELECT is_pinned FROM pane WHERE id = ?",
                arguments: [paneId.uuidString]
            )
            return (repoColumns, paneColumns, repoPinned, panePinned)
        }

        #expect(migrated.0.contains("is_pinned"))
        #expect(!migrated.0.contains("is_favorite"))
        #expect(migrated.1.contains("is_pinned"))
        #expect(migrated.2 == 1)
        #expect(migrated.3 == 0)
    }
}
