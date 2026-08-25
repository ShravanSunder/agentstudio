import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("WorktreeAnnotationMigrationTests")
struct WorktreeAnnotationMigrationTests {
    @Test("local migration creates the complete annotation authority schema")
    func localMigrationCreatesCompleteAnnotationAuthoritySchema() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let tableNames = try databaseQueue.read { database in
            try Set(
                String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            )
        }
        #expect(
            tableNames.isSuperset(of: [
                "annotation_session",
                "annotation_thread",
                "annotation_message",
                "annotation_message_draft",
                "annotation_output_attempt",
                "annotation_output_attempt_message",
                "annotation_output_event",
                "local_recovery_provenance",
            ])
        )
        #expect(!tableNames.contains("annotation_message_version"))
    }

    @Test("message rows own the current saved body and output membership guards its revision")
    func messageRowsOwnCurrentSavedBodyAndOutputMembershipGuardsItsRevision() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let messageColumnRows = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_message)")
        }
        let messageColumns = messageColumnRows.map { row in row["name"] as String }
        let membershipColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_output_attempt_message)")
                .map { row in row["name"] as String }
        }

        #expect(messageColumns.contains("saved_body"))
        #expect(messageColumns.contains("saved_revision"))
        #expect(messageColumns.contains("status"))
        #expect(messageColumns.contains("handled"))
        #expect(messageColumns.contains("viewed_saved_revision"))
        let handledColumn = try #require(
            messageColumnRows.first { row in row["name"] as String == "handled" }
        )
        #expect(handledColumn["notnull"] as Int == 1)
        #expect(handledColumn["dflt_value"] as String? == "0")
        let viewedSavedRevisionColumn = try #require(
            messageColumnRows.first { row in row["name"] as String == "viewed_saved_revision" }
        )
        #expect(viewedSavedRevisionColumn["notnull"] as Int == 0)
        #expect(viewedSavedRevisionColumn["dflt_value"] as String? == nil)
        #expect(membershipColumns.contains("expected_saved_revision"))
        #expect(!membershipColumns.contains("message_version_id"))
    }

    @Test("viewed revision migration preserves populated annotation rows")
    func viewedRevisionMigrationPreservesPopulatedAnnotationRows() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrator.migrate(
            databaseQueue,
            upTo: "007_add_worktree_annotation_message_handled"
        )
        let fixture = try seedViewedRevisionMigrationFixture(in: databaseQueue)

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let preservedRows = try databaseQueue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT id, author_kind, saved_body, saved_revision, status,
                           semantic_revision, handled, viewed_saved_revision
                    FROM annotation_message
                    ORDER BY ordinal
                    """
            )
        }
        #expect(preservedRows.count == 2)
        #expect(preservedRows[0]["id"] as String == fixture.pendingMessageId)
        #expect(preservedRows[0]["author_kind"] as String == "human")
        #expect(preservedRows[0]["saved_body"] as String == "pending")
        #expect(preservedRows[0]["saved_revision"] as Int == 3)
        #expect(preservedRows[0]["status"] as String == "editable")
        #expect(preservedRows[0]["semantic_revision"] as Int == 4)
        #expect(preservedRows[0]["handled"] as Bool == false)
        #expect(preservedRows[0]["viewed_saved_revision"] as Int? == nil)
        #expect(preservedRows[1]["id"] as String == fixture.handledMessageId)
        #expect(preservedRows[1]["status"] as String == "locked")
        #expect(preservedRows[1]["handled"] as Bool == true)
        #expect(preservedRows[1]["viewed_saved_revision"] as Int? == nil)

        let preservedDraftBody = try databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT body FROM annotation_message_draft WHERE message_id = ?",
                arguments: [fixture.pendingMessageId]
            )
        }
        #expect(preservedDraftBody == "draft")

        #expect(throws: DatabaseError.self) {
            try databaseQueue.write { database in
                try database.execute(
                    sql: "UPDATE annotation_message SET viewed_saved_revision = 0 WHERE id = ?",
                    arguments: [fixture.pendingMessageId]
                )
            }
        }
        try databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_message SET viewed_saved_revision = 1 WHERE id = ?",
                arguments: [fixture.pendingMessageId]
            )
        }
        let positiveViewedSavedRevision = try databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT viewed_saved_revision FROM annotation_message WHERE id = ?",
                arguments: [fixture.pendingMessageId]
            )
        }
        #expect(positiveViewedSavedRevision == 1)
    }

    @Test("SQLite accepts future annotation product enum strings")
    func sqliteAcceptsFutureAnnotationProductEnumStrings() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let sessionId = UUIDv7.generate().uuidString
        let threadId = UUIDv7.generate().uuidString
        let messageId = UUIDv7.generate().uuidString
        let attemptId = UUIDv7.generate().uuidString
        let eventId = UUIDv7.generate().uuidString
        let recoveryId = UUIDv7.generate().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO annotation_session(
                        id, repository_id, worktree_id, originating_workspace_id,
                        lifecycle, source_relationship, accepted_source_fingerprint_json,
                        semantic_revision, created_at, updated_at, completed_at
                    ) VALUES (?, 'repository', 'worktree', NULL, 'future_lifecycle',
                        'future_relationship', '{}', 0, 1, 1, NULL)
                    """,
                arguments: [sessionId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_thread(
                        id, session_id, scope, resolution, origin_json, created_ordinal,
                        semantic_revision, created_at, updated_at, resolved_at
                    ) VALUES (?, ?, 'future_scope', 'future_resolution', '{}', 0, 0, 1, 1, NULL)
                    """,
                arguments: [threadId, sessionId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_message(
                        id, thread_id, ordinal, author_kind, saved_body, saved_body_utf8_bytes,
                        saved_revision, status, semantic_revision, created_at, updated_at
                    ) VALUES (?, ?, 0, 'future_author', 'saved', 5, 1, 'future_status', 0, 1, 1)
                    """,
                arguments: [messageId, threadId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_output_attempt(
                        id, session_id, output_kind, state, format_version, content_type,
                        snapshot_json, exact_bytes, destination_path, repeated_from_attempt_id,
                        effect_error, cleanup_error, created_at, updated_at
                    ) VALUES (?, ?, 'future_output', 'future_state', 1, 'text/plain', '{}',
                        X'01', NULL, NULL, NULL, NULL, 1, 1)
                    """,
                arguments: [attemptId, sessionId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_output_attempt_message(
                        attempt_id, message_id, expected_saved_revision, batch_ordinal
                    ) VALUES (?, ?, 1, 0)
                    """,
                arguments: [attemptId, messageId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_output_event(id, attempt_id, event_kind, created_at)
                    VALUES (?, ?, 'future_event', 1)
                    """,
                arguments: [eventId, attemptId]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_recovery_provenance(
                        id, recovery_kind, recovered_at, quarantined_filenames_json,
                        reason, acknowledged_at
                    ) VALUES (?, 'future_recovery', 1, '[]', 'test', NULL)
                    """,
                arguments: [recoveryId]
            )
        }
    }

    @Test("handled migration preserves existing messages as Pending")
    func handledMigrationPreservesExistingMessagesAsPending() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrator.migrate(
            databaseQueue,
            upTo: "006_create_worktree_annotation_schema"
        )
        let sessionId = UUIDv7.generate().uuidString
        let threadId = UUIDv7.generate().uuidString
        let messageId = UUIDv7.generate().uuidString
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO annotation_session(
                        id, repository_id, worktree_id, originating_workspace_id,
                        lifecycle, source_relationship, accepted_source_fingerprint_json,
                        semantic_revision, created_at, updated_at, completed_at
                    ) VALUES (?, 'repository', 'worktree', NULL, 'living',
                        'applicable', '{}', 0, 1, 1, NULL)
                    """,
                arguments: [sessionId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_thread(
                        id, session_id, scope, resolution, origin_json, created_ordinal,
                        semantic_revision, created_at, updated_at, resolved_at
                    ) VALUES (?, ?, 'located', 'open', '{}', 0, 0, 1, 1, NULL)
                    """,
                arguments: [threadId, sessionId]
            )
            try database.execute(
                sql: """
                    INSERT INTO annotation_message(
                        id, thread_id, ordinal, author_kind, saved_body,
                        saved_body_utf8_bytes, saved_revision, status,
                        semantic_revision, created_at, updated_at
                    ) VALUES (?, ?, 0, 'human', 'saved', 5, 1, 'editable', 0, 1, 1)
                    """,
                arguments: [messageId, threadId]
            )
        }

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let handled = try databaseQueue.read { database in
            try Bool.fetchOne(
                database,
                sql: "SELECT handled FROM annotation_message WHERE id = ?",
                arguments: [messageId]
            )
        }
        #expect(handled == false)
    }

    @Test("session discovery is indexed by worktree lineage without workspace partitioning")
    func sessionDiscoveryIsIndexedByWorktreeLineageWithoutWorkspacePartitioning() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let sessionColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_session)")
                .map { row in row["name"] as String }
        }
        let indexColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA index_info(idx_annotation_session_worktree)")
                .map { row in row["name"] as String }
        }
        #expect(sessionColumns.contains("originating_workspace_id"))
        #expect(indexColumns == ["worktree_id", "lifecycle", "source_relationship"])
        #expect(!indexColumns.contains("originating_workspace_id"))
    }

    @Test("output attempts persist canonical batch semantics beside materialized bytes")
    func outputAttemptsPersistCanonicalBatchSemantics() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let outputAttemptColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_output_attempt)")
                .map { row in row["name"] as String }
        }
        #expect(outputAttemptColumns.contains("snapshot_json"))
    }
}

private struct ViewedRevisionMigrationFixture {
    let pendingMessageId: String
    let handledMessageId: String
}

private func seedViewedRevisionMigrationFixture(
    in databaseQueue: DatabaseQueue
) throws -> ViewedRevisionMigrationFixture {
    let sessionId = UUIDv7.generate().uuidString
    let threadId = UUIDv7.generate().uuidString
    let pendingMessageId = UUIDv7.generate().uuidString
    let handledMessageId = UUIDv7.generate().uuidString

    try databaseQueue.write { database in
        try database.execute(
            sql: """
                INSERT INTO annotation_session(
                    id, repository_id, worktree_id, originating_workspace_id,
                    lifecycle, source_relationship, accepted_source_fingerprint_json,
                    semantic_revision, created_at, updated_at, completed_at
                ) VALUES (?, 'repository', 'worktree', NULL, 'living',
                    'applicable', '{}', 2, 1, 2, NULL)
                """,
            arguments: [sessionId]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_thread(
                    id, session_id, scope, resolution, origin_json, created_ordinal,
                    semantic_revision, created_at, updated_at, resolved_at
                ) VALUES (?, ?, 'located', 'open', '{}', 0, 2, 1, 2, NULL)
                """,
            arguments: [threadId, sessionId]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_message(
                    id, thread_id, ordinal, author_kind, saved_body,
                    saved_body_utf8_bytes, saved_revision, status, semantic_revision,
                    created_at, updated_at, handled
                ) VALUES (?, ?, 0, 'human', 'pending', 7, 3, 'editable', 4, 1, 2, 0)
                """,
            arguments: [pendingMessageId, threadId]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_message_draft(
                    message_id, active_edit_token, body, body_utf8_bytes,
                    draft_revision, updated_at
                ) VALUES (?, 'edit-token', 'draft', 5, 2, 2)
                """,
            arguments: [pendingMessageId]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_message(
                    id, thread_id, ordinal, author_kind, saved_body,
                    saved_body_utf8_bytes, saved_revision, status, semantic_revision,
                    created_at, updated_at, handled
                ) VALUES (?, ?, 1, 'human', 'handled', 7, 5, 'locked', 6, 1, 2, 1)
                """,
            arguments: [handledMessageId, threadId]
        )
    }
    return .init(pendingMessageId: pendingMessageId, handledMessageId: handledMessageId)
}
