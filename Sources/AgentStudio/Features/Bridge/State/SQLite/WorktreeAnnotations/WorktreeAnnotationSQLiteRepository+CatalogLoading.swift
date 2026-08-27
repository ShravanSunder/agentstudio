import GRDB

extension WorktreeAnnotationSQLiteRepository {
    func fetchCatalogCapture(worktreeID: String) throws -> WorktreeAnnotationCatalogCapture {
        try databaseWriter.read { database in
            let sessions = try Row.fetchAll(
                database,
                sql: """
                    SELECT id, semantic_revision
                    FROM annotation_session
                    WHERE worktree_id = ?
                    ORDER BY created_at ASC, id ASC
                    """,
                arguments: [worktreeID]
            ).map { row in
                WorktreeAnnotationCatalogSessionRow(
                    sessionID: try decodeIdentity(row["id"] as String),
                    semanticRevision: row["semantic_revision"]
                )
            }
            let threads = try Row.fetchAll(
                database,
                sql: """
                    SELECT thread.id, thread.session_id, thread.scope, thread.created_ordinal
                    FROM annotation_thread AS thread
                    JOIN annotation_session AS session ON session.id = thread.session_id
                    WHERE session.worktree_id = ?
                    ORDER BY thread.session_id ASC, thread.created_ordinal ASC, thread.id ASC
                    """,
                arguments: [worktreeID]
            ).map { row in
                WorktreeAnnotationCatalogThreadRow(
                    threadID: try decodeIdentity(row["id"] as String),
                    sessionID: try decodeIdentity(row["session_id"] as String),
                    scope: try decodeRawValue(row["scope"] as String),
                    createdOrdinal: row["created_ordinal"]
                )
            }
            let messages = try Row.fetchAll(
                database,
                sql: """
                    SELECT message.id, message.thread_id, message.ordinal
                    FROM annotation_message AS message
                    JOIN annotation_thread AS thread ON thread.id = message.thread_id
                    JOIN annotation_session AS session ON session.id = thread.session_id
                    WHERE session.worktree_id = ?
                    ORDER BY message.thread_id ASC, message.ordinal ASC, message.id ASC
                    """,
                arguments: [worktreeID]
            ).map { row in
                WorktreeAnnotationCatalogMessageRow(
                    messageID: try decodeIdentity(row["id"] as String),
                    threadID: try decodeIdentity(row["thread_id"] as String),
                    ordinal: row["ordinal"]
                )
            }
            return WorktreeAnnotationCatalogCapture(
                worktreeID: worktreeID,
                sessions: sessions,
                threads: threads,
                messages: messages
            )
        }
    }
}
