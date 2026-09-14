import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository absence migration")
struct RepositoryAbsenceMigrationTests {
    @Test("existing unavailable repositories migrate without an invented absence date")
    func legacyUnavailableRepositoryHasUnknownAge() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "repository-absence-migration")
        try WorkspaceCoreMigrations.migrator.migrate(database, upTo: "017_create_session_ownership_journal")
        let repositoryID = UUIDv7.generate().uuidString
        try database.write { connection in
            try connection.execute(
                sql: "INSERT INTO repo(id, name, repo_path, stable_key, created_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [repositoryID, "retained", "/tmp/retained", "0123456789abcdef", 0]
            )
            try connection.execute(sql: "INSERT INTO unavailable_repo(repo_id) VALUES (?)", arguments: [repositoryID])
        }

        try WorkspaceCoreMigrations.migrate(database)

        try database.read { connection in
            let unknown = try Int.fetchOne(
                connection,
                sql: "SELECT first_absent_at_utc IS NULL FROM unavailable_repo WHERE repo_id = ?",
                arguments: [repositoryID]
            )
            #expect(unknown == 1)
            #expect(try Int.fetchOne(connection, sql: "SELECT COUNT(*) FROM unavailable_worktree") == 0)
            #expect(try Row.fetchAll(connection, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }
    @Test("legacy missing-main families retain their degraded state without inventing an age")
    func legacyMissingMainFamilyIsMarkedUnconfirmedAtCutover() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "legacy-missing-main-migration")
        try WorkspaceCoreMigrations.migrator.migrate(database, upTo: "017_create_session_ownership_journal")
        let repositoryID = UUIDv7.generate().uuidString
        let worktreeID = UUIDv7.generate().uuidString
        try database.write { connection in
            try connection.execute(
                sql: "INSERT INTO repo(id, name, repo_path, stable_key, created_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [repositoryID, "legacy", "/tmp/legacy-main", "legacy-root-key", 0]
            )
            try connection.execute(
                sql:
                    "INSERT INTO worktree(id, repo_id, name, path, stable_key, is_main_worktree) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [worktreeID, repositoryID, "linked", "/tmp/legacy-linked", "legacy-linked-key", 0]
            )
        }

        try WorkspaceCoreMigrations.migrate(database)

        try database.read { connection in
            let unknownAgeCount = try Int.fetchOne(
                connection,
                sql: "SELECT COUNT(*) FROM unavailable_repo WHERE repo_id = ? AND first_absent_at_utc IS NULL",
                arguments: [repositoryID])
            let retainedCount = try Int.fetchOne(
                connection,
                sql: "SELECT COUNT(*) FROM worktree WHERE id = ?", arguments: [worktreeID])
            let foreignKeyViolations = try Row.fetchAll(connection, sql: "PRAGMA foreign_key_check")
            #expect(unknownAgeCount == 1)
            #expect(retainedCount == 1)
            #expect(foreignKeyViolations.isEmpty)
        }
    }

}
