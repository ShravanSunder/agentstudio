import GRDB

extension WorkspaceLocalMigrations {
    static func registerIPCCredentialSchema(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("012_create_ipc_credential_schema") { database in
            try database.execute(
                sql: """
                    CREATE TABLE local_ipc_credential (
                        credential_namespace TEXT NOT NULL
                            CHECK (credential_namespace IN ('pane', 'diagnostic')),
                        pane_id TEXT,
                        workspace_id TEXT,
                        runtime_id TEXT,
                        generation_id TEXT NOT NULL,
                        verifier_sha256 BLOB NOT NULL
                            CHECK (typeof(verifier_sha256) = 'blob' AND length(verifier_sha256) = 32),
                        status TEXT NOT NULL
                            CHECK (status IN ('prepared', 'active', 'superseded', 'revoked')),
                        CHECK (
                            (credential_namespace = 'pane'
                                AND pane_id IS NOT NULL AND workspace_id IS NOT NULL AND runtime_id IS NULL)
                            OR
                            (credential_namespace = 'diagnostic'
                                AND runtime_id IS NOT NULL AND pane_id IS NULL AND workspace_id IS NULL)
                        )
                    )
                    """
            )
            try database.execute(
                sql: """
                    CREATE UNIQUE INDEX idx_local_ipc_credential_pane_scope_generation
                    ON local_ipc_credential(credential_namespace, pane_id, generation_id)
                    WHERE credential_namespace = 'pane'
                    """
            )
            try database.execute(
                sql: """
                    CREATE UNIQUE INDEX idx_local_ipc_credential_runtime_scope_generation
                    ON local_ipc_credential(credential_namespace, runtime_id, generation_id)
                    WHERE credential_namespace = 'diagnostic'
                    """
            )
        }
    }

    static func registerOpaquePaneCredentialRecords(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("013_create_opaque_pane_credential_records") { database in
            try database.execute(sql: "ALTER TABLE local_ipc_credential RENAME TO local_ipc_credential_012")
            try database.execute(
                sql: """
                    CREATE TABLE local_ipc_credential (
                        credential_namespace TEXT NOT NULL
                            CHECK (credential_namespace IN ('pane', 'diagnostic')),
                        pane_id TEXT,
                        workspace_id TEXT,
                        runtime_id TEXT,
                        credential_record_id TEXT,
                        generation_id TEXT,
                        verifier_sha256 BLOB NOT NULL
                            CHECK (typeof(verifier_sha256) = 'blob' AND length(verifier_sha256) = 32),
                        status TEXT NOT NULL,
                        CHECK (
                            (credential_namespace = 'pane'
                                AND pane_id IS NOT NULL AND workspace_id IS NOT NULL
                                AND runtime_id IS NULL AND credential_record_id IS NOT NULL
                                AND generation_id IS NULL
                                AND status IN ('registered', 'revoked'))
                            OR
                            (credential_namespace = 'diagnostic'
                                AND runtime_id IS NOT NULL AND pane_id IS NULL AND workspace_id IS NULL
                                AND credential_record_id IS NULL AND generation_id IS NOT NULL
                                AND status IN ('prepared', 'active', 'revoked'))
                        )
                    )
                    """
            )
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential(
                        credential_namespace, pane_id, workspace_id, runtime_id,
                        credential_record_id, generation_id, verifier_sha256, status
                    )
                    SELECT credential_namespace, pane_id, workspace_id, runtime_id,
                        CASE WHEN credential_namespace = 'pane' THEN generation_id END,
                        CASE WHEN credential_namespace = 'diagnostic' THEN generation_id END,
                        verifier_sha256,
                        CASE
                            WHEN credential_namespace = 'pane' AND status IN ('active', 'superseded')
                                THEN 'registered'
                            WHEN credential_namespace = 'pane' THEN 'revoked'
                            ELSE status
                        END
                    FROM local_ipc_credential_012
                    """
            )
            try database.execute(sql: "DROP TABLE local_ipc_credential_012")
            try database.execute(
                sql: """
                    CREATE UNIQUE INDEX idx_local_ipc_credential_pane_record
                    ON local_ipc_credential(credential_namespace, pane_id, credential_record_id)
                    WHERE credential_namespace = 'pane'
                    """
            )
            try database.execute(
                sql: """
                    CREATE UNIQUE INDEX idx_local_ipc_credential_runtime_generation
                    ON local_ipc_credential(credential_namespace, runtime_id, generation_id)
                    WHERE credential_namespace = 'diagnostic'
                    """
            )
        }
    }

    /// The reusable debug credential became memory-only, so the diagnostic
    /// namespace, its runtime and generation columns and its index have no
    /// remaining writer. Pane verifiers are the only durable credential.
    static func registerPaneOnlyCredentialRecords(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("014_ipc_credentials_pane_only") { database in
            try database.execute(sql: "ALTER TABLE local_ipc_credential RENAME TO local_ipc_credential_013")
            try database.execute(
                sql: """
                    CREATE TABLE local_ipc_credential (
                        pane_id TEXT NOT NULL,
                        workspace_id TEXT NOT NULL,
                        credential_record_id TEXT NOT NULL,
                        verifier_sha256 BLOB NOT NULL
                            CHECK (typeof(verifier_sha256) = 'blob' AND length(verifier_sha256) = 32),
                        status TEXT NOT NULL CHECK (status IN ('registered', 'revoked'))
                    )
                    """
            )
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential(
                        pane_id, workspace_id, credential_record_id, verifier_sha256, status
                    )
                    SELECT pane_id, workspace_id, credential_record_id, verifier_sha256, status
                    FROM local_ipc_credential_013
                    WHERE credential_namespace = 'pane'
                    """
            )
            try database.execute(sql: "DROP TABLE local_ipc_credential_013")
            try database.execute(
                sql: """
                    CREATE UNIQUE INDEX idx_local_ipc_credential_pane_record
                    ON local_ipc_credential(pane_id, credential_record_id)
                    """
            )
        }
    }
}
