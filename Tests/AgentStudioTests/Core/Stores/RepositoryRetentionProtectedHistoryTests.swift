import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository retention protected history")
struct RepositoryRetentionProtectedHistoryTests {
    @Test("orphan cleanup preserves every annotation row, export bytes, recovery record and pane recency")
    func cleanupPreservesCompleteHistoryGraph() throws {
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: UUIDv7.generate())
        let repositoryID = UUIDv7.generate().uuidString
        let worktreeID = UUIDv7.generate().uuidString
        let sessionID = UUIDv7.generate().uuidString
        let threadID = UUIDv7.generate().uuidString
        let messageID = UUIDv7.generate().uuidString
        let attemptID = UUIDv7.generate().uuidString
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "INSERT INTO cache_repo_enrichment(repo_id, state, updated_at) VALUES (?, 'awaitingOrigin', 0)",
                arguments: [repositoryID])
            try database.execute(
                sql: """
                    INSERT INTO annotation_session(
                        id, repository_id, worktree_id, lifecycle, source_relationship,
                        accepted_source_fingerprint_json, semantic_revision, created_at, updated_at
                    ) VALUES (?, ?, ?, 'living', 'applicable', '{}', 7, 1, 2)
                    """, arguments: [sessionID, repositoryID, worktreeID])
            try database.execute(
                sql: """
                    INSERT INTO annotation_thread(
                        id, session_id, scope, resolution, origin_json, created_ordinal,
                        semantic_revision, created_at, updated_at
                    ) VALUES (?, ?, 'located', 'open', '{"origin":"retained"}', 0, 5, 1, 2)
                    """, arguments: [threadID, sessionID])
            try database.execute(
                sql: """
                    INSERT INTO annotation_message(
                        id, thread_id, ordinal, author_kind, saved_body, saved_body_utf8_bytes,
                        saved_revision, status, semantic_revision, created_at, updated_at, handled
                    ) VALUES (?, ?, 0, 'human', 'saved body', 10, 4, 'editable', 6, 1, 2, 1)
                    """, arguments: [messageID, threadID])
            try database.execute(
                sql: """
                    INSERT INTO annotation_message_draft(
                        message_id, active_edit_token, body, body_utf8_bytes, draft_revision, updated_at
                    ) VALUES (?, 'retained-edit', 'draft body', 10, 8, 2)
                    """, arguments: [messageID])
            try database.execute(
                sql: """
                    INSERT INTO annotation_output_attempt(
                        id, session_id, output_kind, state, format_version, content_type,
                        snapshot_json, exact_bytes, created_at, updated_at
                    ) VALUES (?, ?, 'clipboard_markdown', 'succeeded', 1, 'text/markdown',
                        '{"snapshot":"retained"}', ?, 1, 2)
                    """, arguments: [attemptID, sessionID, Data("saved export bytes".utf8)])
            try database.execute(
                sql: """
                    INSERT INTO annotation_output_attempt_message(attempt_id, message_id, expected_saved_revision, batch_ordinal)
                    VALUES (?, ?, 4, 0)
                    """, arguments: [attemptID, messageID])
            try database.execute(
                sql:
                    "INSERT INTO annotation_output_event(id, attempt_id, event_kind, created_at) VALUES (?, ?, 'copied', 2)",
                arguments: [UUIDv7.generate().uuidString, attemptID])
            try database.execute(
                sql: """
                    INSERT INTO local_recovery_provenance(id, recovery_kind, recovered_at, quarantined_filenames_json, reason)
                    VALUES (?, 'local_rebuild', 2, '[]', 'retained provenance')
                    """, arguments: [UUIDv7.generate().uuidString])
            try database.execute(
                sql: """
                    INSERT INTO local_workspace_entity_recency(
                        workspace_id, entity_kind, entity_key, interaction_kind, last_interacted_at
                    ) VALUES (?, 'pane', ?, 'opened', 2)
                    """, arguments: [UUIDv7.generate().uuidString, UUIDv7.generate().uuidString])
        }
        let before = try protectedRows(in: fixture.databaseQueue)

        let removed = try fixture.repository.pruneOrphanedRepositoryState(
            surviving: .init(repositoryIDs: [], worktreeIDs: [], repositoryKeys: [], worktreeKeys: []), limit: 64)

        #expect(removed == 1)
        #expect(try protectedRows(in: fixture.databaseQueue) == before)
        #expect(before.values.allSatisfy { !$0.isEmpty })
        #expect(try fixture.databaseQueue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check").isEmpty })
    }

    private func protectedRows(in databaseQueue: DatabaseQueue) throws -> [String: [[DatabaseValue]]] {
        let tables = [
            "annotation_session", "annotation_thread", "annotation_message", "annotation_message_draft",
            "annotation_output_attempt", "annotation_output_attempt_message", "annotation_output_event",
            "local_recovery_provenance", "local_workspace_entity_recency",
        ]
        return try databaseQueue.read { database in
            try Dictionary(
                uniqueKeysWithValues: tables.map { table in
                    let rows = try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY rowid")
                    return (table, rows.map { Array($0.databaseValues) })
                })
        }
    }
}
