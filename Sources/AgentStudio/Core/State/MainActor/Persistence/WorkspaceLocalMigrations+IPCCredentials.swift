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
}
