import GRDB

extension WorkspaceLocalMigrations {
    /// Annotation sessions gain a subject: a Git worktree or a local document
    /// outside every worktree. Every existing session is a Git session, so the
    /// rebuild backfills it as one and rewrites its accepted fingerprint to
    /// the subject shape, taking the identity from the row's columns. A row
    /// whose fingerprint is not JSON keeps it verbatim and still fails closed
    /// when read, rather than failing the whole local database. Threads,
    /// messages, drafts, output attempts and their stored bytes are untouched:
    /// GRDB defers foreign-key checks, so dropping and renaming the session
    /// table neither cascades nor rewrites the tables that reference it.
    static func registerAnnotationSubjectVariants(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("017_annotation_subject_variants") { database in
            for statement in annotationSubjectVariantStatements {
                try database.execute(sql: statement)
            }
        }
    }

    private static let annotationSubjectVariantStatements = [
        """
        CREATE TABLE annotation_session_subject_variants (
            id TEXT PRIMARY KEY,
            subject_kind TEXT NOT NULL,
            repository_id TEXT,
            worktree_id TEXT,
            local_document_path TEXT,
            lifecycle TEXT NOT NULL,
            source_relationship TEXT NOT NULL,
            accepted_source_fingerprint_json TEXT NOT NULL,
            accepted_reviewed_subject_json TEXT,
            semantic_revision INTEGER NOT NULL DEFAULT 0 CHECK (semantic_revision >= 0),
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            completed_at REAL
        )
        """,
        """
        INSERT INTO annotation_session_subject_variants (
            id, subject_kind, repository_id, worktree_id, local_document_path,
            lifecycle, source_relationship, accepted_source_fingerprint_json,
            accepted_reviewed_subject_json, semantic_revision, created_at, updated_at, completed_at
        )
        SELECT
            id, 'git', repository_id, worktree_id, NULL,
            lifecycle, source_relationship,
            CASE WHEN json_valid(accepted_source_fingerprint_json) THEN json_set(
                json_remove(accepted_source_fingerprint_json, '$.repositoryID', '$.worktreeID'),
                '$.subject',
                json_object('kind', 'git', 'repositoryID', repository_id, 'worktreeID', worktree_id)
            ) ELSE accepted_source_fingerprint_json END,
            accepted_reviewed_subject_json, semantic_revision, created_at, updated_at, completed_at
        FROM annotation_session
        """,
        "DROP TABLE annotation_session",
        "ALTER TABLE annotation_session_subject_variants RENAME TO annotation_session",
        """
        CREATE INDEX idx_annotation_session_worktree
        ON annotation_session(worktree_id, lifecycle, source_relationship)
        """,
        """
        CREATE INDEX idx_annotation_session_repository_lifecycle_relationship
        ON annotation_session(repository_id, lifecycle, source_relationship)
        """,
        """
        CREATE INDEX idx_annotation_session_local_document
        ON annotation_session(subject_kind, local_document_path, lifecycle)
        """,
    ]
}
