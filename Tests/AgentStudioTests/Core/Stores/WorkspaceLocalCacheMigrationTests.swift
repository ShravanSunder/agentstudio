import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalCacheMigrationTests")
struct WorkspaceLocalCacheMigrationTests {
    @Test("cache rows round trip without local rows")
    func cacheRowsRoundTripWithoutLocalRows() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let repoId = UUID().uuidString
        let worktreeId = UUID().uuidString

        let restored = try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO cache_metadata(workspace_id, source_revision, last_rebuilt_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [workspaceId, 7, 1.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO cache_repo_enrichment(
                        repo_id, workspace_id, state, origin, upstream, group_key, remote_slug,
                        organization_name, display_name, updated_at, payload_json
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    repoId,
                    workspaceId,
                    "available",
                    "git@github.com:example/project.git",
                    "origin/main",
                    "example",
                    "example/project",
                    "example",
                    "project",
                    2.0,
                    #"{"state":"available"}"#,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO cache_worktree_enrichment(
                        worktree_id, workspace_id, repo_id, branch, is_main_worktree, updated_at, payload_json
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    worktreeId,
                    workspaceId,
                    repoId,
                    "main",
                    1,
                    3.0,
                    #"{"branch":"main"}"#,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO cache_pull_request_count(worktree_id, workspace_id, repo_id, count, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [worktreeId, workspaceId, repoId, 5, 4.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO cache_notification_count(worktree_id, workspace_id, repo_id, count, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [worktreeId, workspaceId, repoId, 6, 5.0]
            )
            return try Row.fetchOne(
                database,
                sql: """
                    SELECT metadata.source_revision, repo.display_name, worktree.branch,
                           pull_request.count AS pull_request_count, notification.count AS notification_count
                    FROM cache_metadata metadata
                    JOIN cache_repo_enrichment repo ON repo.workspace_id = metadata.workspace_id
                    JOIN cache_worktree_enrichment worktree ON worktree.repo_id = repo.repo_id
                    JOIN cache_pull_request_count pull_request ON pull_request.worktree_id = worktree.worktree_id
                    JOIN cache_notification_count notification ON notification.worktree_id = worktree.worktree_id
                    WHERE metadata.workspace_id = ?
                    """,
                arguments: [workspaceId]
            )
        }

        #expect(restored?["source_revision"] as Int? == 7)
        #expect(restored?["display_name"] as String? == "project")
        #expect(restored?["branch"] as String? == "main")
        #expect(restored?["pull_request_count"] as Int? == 5)
        #expect(restored?["notification_count"] as Int? == 6)
    }

    @Test("cache counters reject negative values")
    func cacheCountersRejectNegativeValues() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString

        expectLocalCacheDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO cache_metadata(workspace_id, source_revision, last_rebuilt_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [workspaceId, -1, nil]
                )
            }
        }

        expectLocalCacheDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO cache_pull_request_count(worktree_id, workspace_id, repo_id, count, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, workspaceId, nil, -1, 1.0]
                )
            }
        }
    }

    @Test("cache worktree enrichment rejects non boolean main-worktree value")
    func cacheWorktreeEnrichmentRejectsNonBooleanMainWorktreeValue() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        expectLocalCacheDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO cache_worktree_enrichment(
                            worktree_id, workspace_id, repo_id, branch, is_main_worktree, updated_at, payload_json
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        UUID().uuidString,
                        UUID().uuidString,
                        "main",
                        4,
                        1.0,
                        nil,
                    ]
                )
            }
        }
    }
}

private func expectLocalCacheDatabaseError(containing expectedMessage: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected DatabaseError containing '\(expectedMessage)'")
    } catch let error as DatabaseError {
        #expect(error.message?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Expected DatabaseError, got \(error)")
    }
}
