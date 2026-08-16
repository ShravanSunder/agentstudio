import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Workspace core pane association migration")
struct WorkspaceCorePaneAssociationMigrationTests {
    @Test("migration 016 adds soft pane association columns with only the pair check")
    func migration016AddsSoftAssociationColumnsWithOnlyPairCheck() throws {
        // Arrange
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.migration-016.schema"
        )
        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "015_drop_pane_topology_facets"
        )

        // Act
        try WorkspaceCoreMigrations.migrate(databaseQueue)

        // Assert
        let schema = try databaseQueue.read { database in
            let paneColumns = try Row.fetchAll(database, sql: "PRAGMA table_info(pane)")
            let paneColumnNullability = Dictionary(
                uniqueKeysWithValues: paneColumns.map { row in
                    (row["name"] as String, row["notnull"] as Int)
                }
            )
            let paneSQL = try #require(
                try String.fetchOne(
                    database,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pane'"
                )
            )
            let paneForeignKeyColumns = try Row.fetchAll(database, sql: "PRAGMA foreign_key_list(pane)")
                .map { row in row["from"] as String }
            let paneTriggerSQL = try Row.fetchAll(
                database,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'pane'"
            )
            .compactMap { row in row["sql"] as String? }
            return (paneColumnNullability, paneSQL, paneForeignKeyColumns, paneTriggerSQL)
        }

        #expect(schema.0["facet_repo_id"] == 0)
        #expect(schema.0["facet_worktree_id"] == 0)
        #expect(schema.1.contains("facet_repo_id IS NULL"))
        #expect(schema.1.contains("facet_worktree_id IS NULL"))
        #expect(!schema.2.contains("facet_repo_id"))
        #expect(!schema.2.contains("facet_worktree_id"))
        #expect(!schema.3.contains { $0.contains("facet_repo_id") || $0.contains("facet_worktree_id") })
    }

    @Test("pane association check rejects partial pairs and accepts dangling UUID pairs")
    func paneAssociationCheckRejectsPartialAndAcceptsDanglingPair() throws {
        // Arrange
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.migration-016.soft-references"
        )
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let workspaceID = UUIDv7.generate()
        let partialPaneID = UUIDv7.generate()
        let danglingPaneID = UUIDv7.generate()
        let danglingRepoID = UUIDv7.generate()
        let danglingWorktreeID = UUIDv7.generate()
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace(id, name, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [workspaceID.uuidString, "Association", 1.0, 1.0]
            )
        }

        // Act / Assert
        #expect(throws: DatabaseError.self) {
            try databaseQueue.write { database in
                try insertAssociationMigrationPane(
                    database,
                    workspaceID: workspaceID,
                    paneID: partialPaneID,
                    repoID: danglingRepoID,
                    worktreeID: nil
                )
            }
        }

        try databaseQueue.write { database in
            try insertAssociationMigrationPane(
                database,
                workspaceID: workspaceID,
                paneID: danglingPaneID,
                repoID: danglingRepoID,
                worktreeID: danglingWorktreeID
            )
        }
        let storedPair = try databaseQueue.read { database in
            let row = try #require(
                try Row.fetchOne(
                    database,
                    sql: "SELECT facet_repo_id, facet_worktree_id FROM pane WHERE id = ?",
                    arguments: [danglingPaneID.uuidString]
                )
            )
            return (row["facet_repo_id"] as String, row["facet_worktree_id"] as String)
        }
        #expect(storedPair.0 == danglingRepoID.uuidString)
        #expect(storedPair.1 == danglingWorktreeID.uuidString)
    }
}

private func insertAssociationMigrationPane(
    _ database: Database,
    workspaceID: UUID,
    paneID: UUID,
    repoID: UUID?,
    worktreeID: UUID?
) throws {
    try database.execute(
        sql: """
            INSERT INTO pane(
                id, workspace_id, content_type, execution_backend,
                title, cwd, facet_repo_id, facet_worktree_id,
                residency_kind, kind, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            paneID.uuidString,
            workspaceID.uuidString,
            SQLitePaneContentTypeStorage.storageValue(for: .terminal),
            "local",
            "Terminal",
            "/tmp/agentstudio/association",
            repoID?.uuidString,
            worktreeID?.uuidString,
            "active",
            "leaf",
            1.0,
            1.0,
        ]
    )
}
