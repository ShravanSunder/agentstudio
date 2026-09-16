import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("IPC credential local schema migration")
struct WorkspaceLocalIPCCredentialMigrationTests {
    @Test("migrations 012 and 013 add opaque IPC credentials while preserving initialized local data")
    func credentialMigrationsPreserveInitializedLocalData() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.ipc-credential-migration"
        )
        try WorkspaceLocalMigrations.migrator.migrate(
            database,
            upTo: "011_create_sessions_ingestion_schema"
        )
        try seedPreIPCCredentialMigrationData(database)

        try WorkspaceLocalMigrations.migrate(database)
        try WorkspaceLocalMigrations.migrate(database)

        try database.read { connection in
            let completedMigrations = try WorkspaceLocalMigrations.migrator.completedMigrations(connection)
            #expect(completedMigrations.last == "013_create_opaque_pane_credential_records")
            #expect(completedMigrations.filter { $0 == "012_create_ipc_credential_schema" }.count == 1)
            #expect(completedMigrations.filter { $0 == "013_create_opaque_pane_credential_records" }.count == 1)
            #expect(try connection.tableExists("local_ipc_credential"))
            #expect(
                try String.fetchOne(
                    connection,
                    sql: "SELECT filter_text FROM local_window_state WHERE window_id = 'retained-window'"
                ) == "retained filter"
            )
            #expect(
                try String.fetchOne(
                    connection,
                    sql: "SELECT title FROM local_notification_inbox_item WHERE id = 'retained-inbox-item'"
                ) == "Retained Inbox Item"
            )
            #expect(
                try String.fetchOne(
                    connection,
                    sql: "SELECT provider_conversation_id FROM sessions_conversation WHERE id = 'retained-conversation'"
                ) == "provider-conversation"
            )
            #expect(
                try String.fetchOne(
                    connection,
                    sql: "SELECT outcome_kind FROM sessions_operation WHERE correlation_id = 'retained-correlation'"
                ) == "retainedOutcome"
            )
            #expect(try String.fetchAll(connection, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    @Test("credential schema has only verifier and discriminated scope columns")
    func credentialSchemaHasExactColumnsAndAcceptsValidScopes() throws {
        let database = try migratedIPCCredentialDatabase()

        try database.write { connection in
            let columns = try Row.fetchAll(
                connection,
                sql: "PRAGMA table_info(local_ipc_credential)"
            ).map { $0["name"] as String }
            #expect(
                columns == [
                    "credential_namespace", "pane_id", "workspace_id", "runtime_id",
                    "credential_record_id", "generation_id", "verifier_sha256", "status",
                ]
            )
            try insertPaneCredential(connection, verifier: Data(repeating: 0xA5, count: 32))
            try insertDiagnosticCredential(connection, verifier: Data(repeating: 0x5A, count: 32))
            let verifierStorage = try Row.fetchAll(
                connection,
                sql:
                    "SELECT typeof(verifier_sha256) AS storage_type, length(verifier_sha256) AS byte_count FROM local_ipc_credential ORDER BY credential_namespace"
            )
            #expect(verifierStorage.map { $0["storage_type"] as String } == ["blob", "blob"])
            #expect(verifierStorage.map { $0["byte_count"] as Int } == [32, 32])
        }
    }

    @Test("credential verifier requires a 32 byte SQLite blob")
    func credentialVerifierRejectsTextAndShortBlob() throws {
        let database = try migratedIPCCredentialDatabase()

        try database.write { connection in
            expectCredentialConstraintFailure {
                try insertPaneCredential(connection, verifierSQL: "'12345678901234567890123456789012'")
            }
            expectCredentialConstraintFailure {
                try insertPaneCredential(connection, verifier: Data(repeating: 0xA5, count: 31))
            }
        }
    }

    @Test("credential scope requires exactly one complete namespace shape")
    func credentialScopeRejectsMissingAndMixedFields() throws {
        let database = try migratedIPCCredentialDatabase()

        try database.write { connection in
            expectCredentialConstraintFailure {
                try insertCredential(
                    connection,
                    values: .init(
                        namespace: "pane",
                        paneID: nil,
                        workspaceID: "workspace-1",
                        credentialRecordID: "record-missing-pane"
                    )
                )
            }
            expectCredentialConstraintFailure {
                try insertCredential(
                    connection,
                    values: .init(
                        namespace: "diagnostic",
                        paneID: "pane-1",
                        workspaceID: "workspace-1",
                        runtimeID: "runtime-1",
                        credentialRecordID: "record-mixed",
                        generationID: "generation-mixed"
                    )
                )
            }
            expectCredentialConstraintFailure {
                try insertCredential(
                    connection,
                    values: .init(
                        namespace: "future",
                        runtimeID: "runtime-1",
                        generationID: "generation-unknown-namespace"
                    )
                )
            }
        }
    }

    @Test("credential status accepts only the namespace lifecycle")
    func credentialStatusAcceptsOnlyFiniteLifecycle() throws {
        let database = try migratedIPCCredentialDatabase()

        try database.write { connection in
            for status in ["registered", "revoked"] {
                try insertCredential(
                    connection,
                    values: .init(
                        namespace: "pane",
                        paneID: "pane-\(status)",
                        workspaceID: "workspace-1",
                        credentialRecordID: "record-\(status)",
                        status: status
                    )
                )
            }
            for status in ["prepared", "active", "revoked"] {
                try insertCredential(
                    connection,
                    values: .init(
                        namespace: "diagnostic",
                        runtimeID: "runtime-\(status)",
                        generationID: "generation-\(status)",
                        status: status
                    )
                )
            }
            expectCredentialConstraintFailure {
                try insertCredential(
                    connection,
                    values: .init(
                        namespace: "pane",
                        paneID: "pane-unknown",
                        workspaceID: "workspace-1",
                        credentialRecordID: "record-unknown",
                        status: "future"
                    )
                )
            }
        }
    }

    @Test("pane uniqueness uses opaque record while distinct same-pane records coexist")
    func credentialUniquenessUsesOpaqueRecordIdentity() throws {
        let database = try migratedIPCCredentialDatabase()

        try database.write { connection in
            try insertPaneCredential(connection, workspaceID: "workspace-1")
            expectCredentialConstraintFailure(containing: "UNIQUE constraint failed") {
                try insertPaneCredential(connection, workspaceID: "workspace-2")
            }
            try insertPaneCredential(connection, credentialRecordID: "second-record")
            try insertDiagnosticCredential(connection)
            expectCredentialConstraintFailure(containing: "UNIQUE constraint failed") {
                try insertDiagnosticCredential(connection)
            }
            #expect(
                try Int.fetchOne(connection, sql: "SELECT COUNT(*) FROM local_ipc_credential") == 3
            )
        }
    }

    @Test("migration 013 preserves and remaps already-applied 012 pane and diagnostic rows")
    func migration013PreservesExistingCredentialRows() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.ipc-013")
        try WorkspaceLocalMigrations.migrator.migrate(database, upTo: "012_create_ipc_credential_schema")
        try database.write { connection in
            try connection.execute(
                sql: """
                    INSERT INTO local_ipc_credential VALUES
                    ('pane', 'pane-a', 'workspace-a', NULL, 'record-active', ?, 'active'),
                    ('pane', 'pane-a', 'workspace-a', NULL, 'record-superseded', ?, 'superseded'),
                    ('pane', 'pane-b', 'workspace-a', NULL, 'record-prepared', ?, 'prepared'),
                    ('diagnostic', NULL, NULL, 'runtime-a', 'generation-a', ?, 'active')
                    """,
                arguments: [
                    Data(repeating: 0x01, count: 32), Data(repeating: 0x02, count: 32),
                    Data(repeating: 0x03, count: 32), Data(repeating: 0x04, count: 32),
                ]
            )
        }
        try WorkspaceLocalMigrations.migrate(database)
        try database.read { connection in
            let rows = try Row.fetchAll(
                connection,
                sql: """
                    SELECT credential_namespace, credential_record_id, generation_id, status
                    FROM local_ipc_credential ORDER BY verifier_sha256
                    """
            )
            #expect(rows.map { $0["status"] as String } == ["registered", "registered", "revoked", "active"])
            #expect(rows[0]["credential_record_id"] as String? == "record-active")
            #expect(rows[1]["credential_record_id"] as String? == "record-superseded")
            #expect(rows[3]["generation_id"] as String? == "generation-a")
        }
    }
}

private func seedPreIPCCredentialMigrationData(_ database: DatabaseQueue) throws {
    try database.write { connection in
        #expect(try !connection.tableExists("local_ipc_credential"))
        try connection.execute(
            sql: """
                INSERT INTO local_window_state(
                    window_id, window_role, sidebar_width, window_frame_json,
                    filter_text, is_filter_visible, sidebar_collapsed,
                    sidebar_surface, updated_at
                ) VALUES ('retained-window', 'main', 280, NULL, 'retained filter', 1, 0, 'repos', 10)
                """
        )
        try connection.execute(
            sql: """
                INSERT INTO local_notification_inbox_item(
                    workspace_id, id, timestamp, kind, title, source_kind,
                    is_read, is_dismissed_from_pane_inbox
                ) VALUES (
                    'retained-workspace', 'retained-inbox-item', 11,
                    'agentActivity', 'Retained Inbox Item', 'pane', 0, 0
                )
                """
        )
        try connection.execute(
            sql: """
                INSERT INTO sessions_conversation(
                    id, provider_identifier, provider_conversation_id,
                    created_at, last_reported_at
                ) VALUES (
                    'retained-conversation', 'fixture-provider',
                    'provider-conversation', 12, 13
                )
                """
        )
        try connection.execute(
            sql: """
                INSERT INTO sessions_operation(
                    operation_scope, correlation_id, operation_kind,
                    semantic_fingerprint, outcome_kind, created_at
                ) VALUES (
                    'retained-scope', 'retained-correlation', 'prepareForLaunch',
                    'retained-fingerprint', 'retainedOutcome', 14
                )
                """
        )
    }
}

private func migratedIPCCredentialDatabase() throws -> DatabaseQueue {
    let database = try SQLiteDatabaseFactory.makeInMemoryQueue(
        label: "AgentStudio.sqlite.ipc-credential-schema"
    )
    try WorkspaceLocalMigrations.migrate(database)
    return database
}

private func insertPaneCredential(
    _ database: Database,
    workspaceID: String = "workspace-1",
    credentialRecordID: String = "shared-record",
    verifier: Data = Data(repeating: 0xA5, count: 32)
) throws {
    try insertCredential(
        database,
        values: .init(
            namespace: "pane",
            paneID: "pane-1",
            workspaceID: workspaceID,
            credentialRecordID: credentialRecordID,
            verifier: verifier,
            status: "registered"
        )
    )
}

private func insertPaneCredential(_ database: Database, verifierSQL: String) throws {
    try database.execute(
        sql: """
            INSERT INTO local_ipc_credential(
                credential_namespace, pane_id, workspace_id, runtime_id,
                credential_record_id, generation_id, verifier_sha256, status
            ) VALUES (
                'pane', 'pane-1', 'workspace-1', NULL,
                'text-verifier-record', NULL, \(verifierSQL), 'registered'
            )
            """
    )
}

private func insertDiagnosticCredential(
    _ database: Database,
    verifier: Data = Data(repeating: 0x5A, count: 32)
) throws {
    try insertCredential(
        database,
        values: .init(
            namespace: "diagnostic",
            runtimeID: "runtime-1",
            generationID: "shared-generation",
            verifier: verifier,
            status: "prepared"
        )
    )
}

private struct CredentialInsertValues {
    let namespace: String
    var paneID: String?
    var workspaceID: String?
    var runtimeID: String?
    var credentialRecordID: String?
    var generationID: String?
    var verifier: Data
    var status: String

    init(
        namespace: String,
        paneID: String? = nil,
        workspaceID: String? = nil,
        runtimeID: String? = nil,
        credentialRecordID: String? = nil,
        generationID: String? = nil,
        verifier: Data = Data(repeating: 0xA5, count: 32),
        status: String = "prepared"
    ) {
        self.namespace = namespace
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.runtimeID = runtimeID
        self.credentialRecordID = credentialRecordID
        self.generationID = generationID
        self.verifier = verifier
        self.status = status
    }
}

private func insertCredential(
    _ database: Database,
    values: CredentialInsertValues
) throws {
    try database.execute(
        sql: """
            INSERT INTO local_ipc_credential(
                credential_namespace, pane_id, workspace_id, runtime_id,
                credential_record_id, generation_id, verifier_sha256, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            values.namespace, values.paneID, values.workspaceID, values.runtimeID,
            values.credentialRecordID, values.generationID, values.verifier, values.status,
        ]
    )
}

private func expectCredentialConstraintFailure(
    containing expectedMessage: String = "CHECK constraint failed",
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected credential schema constraint failure")
    } catch let error as DatabaseError {
        #expect(error.message?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Expected SQLite constraint failure, received \(type(of: error))")
    }
}
