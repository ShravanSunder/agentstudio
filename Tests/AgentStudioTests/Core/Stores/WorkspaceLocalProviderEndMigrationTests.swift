import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Provider end local migration")
struct WorkspaceLocalProviderEndMigrationTests {
    @Test("the six resume-evidence columns use TEXT or INTEGER and add no triggers")
    func resumeEvidenceSchemaIsTyped() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.provider-end-schema")
        try WorkspaceLocalMigrations.migrate(database)

        try database.read { connection in
            let rows = try Row.fetchAll(connection, sql: "PRAGMA table_info(sessions_pane_binding)")
            let expectedColumns = [
                "provider_end_reason", "provider_end_reason_text", "provider_ended_at",
                "started_from_historical_report", "evidence_unordered", "unordered_fence_sequence",
            ]
            for columnName in expectedColumns {
                let column = try #require(rows.first { ($0["name"] as String) == columnName })
                let columnType: String = column["type"]
                #expect(["TEXT", "INTEGER"].contains(columnType))
            }
            for columnName in ["started_from_historical_report", "evidence_unordered", "unordered_fence_sequence"] {
                let column = try #require(rows.first { ($0["name"] as String) == columnName })
                #expect((column["type"] as String) == "INTEGER")
            }
            #expect(
                try Int.fetchOne(
                    connection,
                    sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'sessions_pane_binding'"
                ) == 0)
        }
    }

    @Test("upgrading preserves an existing binding with no fabricated provider end and ordered defaults")
    func upgradePreservesBindingWithEmptyEvidence() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.provider-end-upgrade")
        try WorkspaceLocalMigrations.migrator.migrate(database, upTo: "014_ipc_credentials_pane_only")
        let bindingGenerationId = UUIDv7.generate()
        try seedLegacyBinding(database: database, bindingGenerationId: bindingGenerationId)

        try WorkspaceLocalMigrations.migrate(database)
        try WorkspaceLocalMigrations.migrate(database)

        try database.write { connection in
            let fetchedRow = try Row.fetchOne(
                connection, sql: "SELECT * FROM sessions_pane_binding WHERE binding_generation_id = ?",
                arguments: [bindingGenerationId.uuidString]
            )
            let row = try #require(fetchedRow)
            #expect((row["status"] as String) == "active")
            #expect((row["started_at"] as Double) == 1)
            #expect((row["provider_end_reason"] as String?) == nil)
            #expect((row["provider_end_reason_text"] as String?) == nil)
            #expect((row["provider_ended_at"] as String?) == nil)
            #expect((row["started_from_historical_report"] as Int) == 0)
            #expect((row["evidence_unordered"] as Int) == 0)
            #expect((row["unordered_fence_sequence"] as Int64?) == nil)
            for columnName in ["started_from_historical_report", "evidence_unordered"] {
                #expect(throws: DatabaseError.self) {
                    try connection.execute(sql: "UPDATE sessions_pane_binding SET \(columnName) = 2")
                }
            }
            // Future reason cases remain representable: only the two new booleans get CHECKs.
            try connection.execute(sql: "UPDATE sessions_pane_binding SET provider_end_reason = 'future-reason-case'")
            #expect(try String.fetchAll(connection, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    private func seedLegacyBinding(database: DatabaseQueue, bindingGenerationId: UUID) throws {
        let conversationId = UUIDv7.generate()
        try database.write { connection in
            try connection.execute(
                sql: """
                    INSERT INTO sessions_conversation (
                        id, provider_identifier, provider_conversation_id, created_at, last_reported_at
                    ) VALUES (?, 'codex', ?, 1, 1)
                    """,
                arguments: [conversationId.uuidString, UUIDv7.generate().uuidString]
            )
            try connection.execute(
                sql: """
                    INSERT INTO sessions_operation (
                        operation_scope, correlation_id, operation_kind, semantic_fingerprint, outcome_kind, created_at
                    ) VALUES ('legacy', ?, 'bind', 'legacy-fingerprint', 'binding', 1)
                    """,
                arguments: [UUIDv7.generate().uuidString]
            )
            let revision = connection.lastInsertedRowID
            try connection.execute(
                sql: """
                    INSERT INTO sessions_pane_binding (
                        binding_generation_id, pane_id, conversation_id, source_generation_id,
                        origin, status, transition_occurrence_id, started_at, ended_at, committed_revision
                    ) VALUES (?, ?, ?, ?, 'reported', 'active', ?, 1, NULL, ?)
                    """,
                arguments: [
                    bindingGenerationId.uuidString, UUIDv7.generate().uuidString, conversationId.uuidString,
                    UUIDv7.generate().uuidString, UUIDv7.generate().uuidString, revision,
                ]
            )
        }
    }
}
