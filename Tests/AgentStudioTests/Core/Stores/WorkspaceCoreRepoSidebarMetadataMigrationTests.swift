import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCore repo sidebar metadata migration")
struct WorkspaceCoreRepoSidebarMetadataMigrationTests {
    @Test("migration 011 adds repo sidebar metadata without repo worktree or pane color columns")
    func migration011AddsRepoSidebarMetadataWithoutRepoWorktreeOrPaneColorColumns() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let workspaceId = UUID().uuidString
        let repoId = UUID().uuidString
        let worktreeId = UUID().uuidString
        let tabId = UUID().uuidString

        try WorkspaceCoreMigrations.migrator.migrate(databaseQueue, upTo: "010_drop_pane_tag")
        try databaseQueue.write { database in
            try insertWorkspace(database, workspaceId: workspaceId)
            try insertRepo(database, workspaceId: workspaceId, repoId: repoId)
            try insertWorktree(database, workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
            try insertTabShell(database, workspaceId: workspaceId, tabId: tabId, name: "Main", sortIndex: 0)
        }

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE repo
                    SET is_favorite = ?, note = ?
                    WHERE id = ?
                    """,
                arguments: [1, "repo note", repoId]
            )
            try database.execute(
                sql: """
                    UPDATE worktree
                    SET note = ?
                    WHERE id = ?
                    """,
                arguments: ["worktree note", worktreeId]
            )
            try database.execute(
                sql: """
                    UPDATE tab_shell
                    SET color_hex = ?
                    WHERE id = ?
                    """,
                arguments: ["#58C4FF", tabId]
            )
            try database.execute(
                sql: """
                    INSERT INTO repo_tag(repo_id, tag)
                    VALUES (?, ?)
                    """,
                arguments: [repoId, "favorite-client"]
            )
        }

        let repoColumns = try databaseQueue.read { database in
            try columnInfo(database, tableName: "repo")
        }
        let worktreeColumns = try databaseQueue.read { database in
            try columnInfo(database, tableName: "worktree")
        }
        let tabShellColumns = try databaseQueue.read { database in
            try columnInfo(database, tableName: "tab_shell")
        }
        let repoTagExists = try databaseQueue.read { database in
            try tableExists(database, tableName: "repo_tag")
        }
        let paneTagExists = try databaseQueue.read { database in
            try tableExists(database, tableName: "pane_tag")
        }
        #expect(repoColumns["is_favorite"] != nil)
        #expect((repoColumns["is_favorite"]?["notnull"] as Int?) == 1)
        #expect((repoColumns["is_favorite"]?["dflt_value"] as String?) == "0")
        #expect(repoColumns["note"] != nil)
        #expect(repoColumns["color_hex"] == nil)
        #expect(worktreeColumns["note"] != nil)
        #expect(worktreeColumns["color_hex"] == nil)
        #expect(tabShellColumns["color_hex"] != nil)
        #expect(tabShellColumns["note"] == nil)
        #expect(repoTagExists)
        #expect(!paneTagExists)

        let restored = try databaseQueue.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT repo.is_favorite, repo.note, worktree.note AS worktree_note,
                           tab_shell.color_hex, repo_tag.tag
                    FROM repo
                    JOIN worktree ON worktree.repo_id = repo.id
                    JOIN tab_shell ON tab_shell.workspace_id = repo.workspace_id
                    JOIN repo_tag ON repo_tag.repo_id = repo.id
                    WHERE repo.id = ?
                    """,
                arguments: [repoId]
            )
        }
        #expect(restored?["is_favorite"] as Int? == 1)
        #expect(restored?["note"] as String? == "repo note")
        #expect(restored?["worktree_note"] as String? == "worktree note")
        #expect(restored?["color_hex"] as String? == "#58C4FF")
        #expect(restored?["tag"] as String? == "favorite-client")
    }

    private func insertWorkspace(_ database: Database, workspaceId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO workspace(id, name, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [workspaceId, "SQLite Workspace", 1.0, 1.0]
        )
    }

    private func insertRepo(_ database: Database, workspaceId: String, repoId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO repo(id, workspace_id, name, repo_path, stable_key, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [repoId, workspaceId, "repo", "/tmp/repo", "repo", 1.0]
        )
    }

    private func insertWorktree(
        _ database: Database,
        workspaceId: String,
        repoId: String,
        worktreeId: String
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO worktree(id, workspace_id, repo_id, name, path, stable_key, is_main_worktree)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [worktreeId, workspaceId, repoId, "worktree", "/tmp/worktree", "worktree", 0]
        )
    }

    private func insertTabShell(
        _ database: Database,
        workspaceId: String,
        tabId: String,
        name: String,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_shell(id, workspace_id, name, sort_index)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [tabId, workspaceId, name, sortIndex]
        )
    }

    private func tableExists(_ database: Database, tableName: String) throws -> Bool {
        try String.fetchOne(
            database,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                AND name = ?
                """,
            arguments: [tableName]
        ) != nil
    }

    private func columnInfo(_ database: Database, tableName: String) throws -> [String: Row] {
        try Dictionary(
            uniqueKeysWithValues: Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))").map { row in
                (row["name"] as String, row)
            }
        )
    }
}
