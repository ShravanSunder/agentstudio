import GRDB

extension WorktreeAnnotationSQLiteRepository {
    /// Reads only requested catalog identities in one SQLite read transaction.
    /// Missing rows stay absent so N10 can emit their deletion tombstones.
    func fetchCurrentCatalogEntries(
        worktreeID: String,
        keys: Set<WorktreeAnnotationCatalogKey>
    ) throws -> [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry] {
        try databaseWriter.read { database in
            var entries: [WorktreeAnnotationCatalogKey: WorktreeAnnotationCatalogEntry] = [:]
            for key in keys {
                switch key {
                case .session(let id):
                    guard
                        let row = try Row.fetchOne(
                            database,
                            sql: """
                                SELECT id, semantic_revision FROM annotation_session
                                WHERE id = ? AND worktree_id = ?
                                """,
                            arguments: [id.databaseValue, worktreeID]
                        )
                    else { continue }
                    entries[key] = .session(
                        try .init(
                            sessionID: decodeIdentity(row["id"] as String),
                            semanticRevision: row["semantic_revision"]
                        )
                    )
                case .thread(let id):
                    guard
                        let row = try Row.fetchOne(
                            database,
                            sql: """
                                SELECT thread.id, thread.session_id, thread.scope, thread.created_ordinal
                                FROM annotation_thread AS thread
                                JOIN annotation_session AS session ON session.id = thread.session_id
                                WHERE thread.id = ? AND session.worktree_id = ?
                                """,
                            arguments: [id.databaseValue, worktreeID]
                        )
                    else { continue }
                    entries[key] = .thread(
                        try .init(
                            threadID: decodeIdentity(row["id"] as String),
                            sessionID: decodeIdentity(row["session_id"] as String),
                            scope: decodeRawValue(row["scope"] as String),
                            createdOrdinal: row["created_ordinal"]
                        )
                    )
                case .message(let id):
                    guard
                        let row = try Row.fetchOne(
                            database,
                            sql: """
                                SELECT message.id, message.thread_id, message.ordinal
                                FROM annotation_message AS message
                                JOIN annotation_thread AS thread ON thread.id = message.thread_id
                                JOIN annotation_session AS session ON session.id = thread.session_id
                                WHERE message.id = ? AND session.worktree_id = ?
                                """,
                            arguments: [id.databaseValue, worktreeID]
                        )
                    else { continue }
                    entries[key] = .message(
                        try .init(
                            messageID: decodeIdentity(row["id"] as String),
                            threadID: decodeIdentity(row["thread_id"] as String),
                            ordinal: row["ordinal"]
                        )
                    )
                }
            }
            return entries
        }
    }

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
