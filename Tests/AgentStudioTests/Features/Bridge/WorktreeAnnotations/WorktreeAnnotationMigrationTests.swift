import AgentStudioInfrastructure
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

        let messageColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_message)")
                .map { row in row["name"] as String }
        }
        let membershipColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_output_attempt_message)")
                .map { row in row["name"] as String }
        }

        #expect(messageColumns.contains("saved_body"))
        #expect(messageColumns.contains("saved_revision"))
        #expect(messageColumns.contains("status"))
        #expect(membershipColumns.contains("expected_saved_revision"))
        #expect(!membershipColumns.contains("message_version_id"))
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
