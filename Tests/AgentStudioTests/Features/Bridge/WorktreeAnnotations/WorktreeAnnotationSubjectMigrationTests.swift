import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation subject migration")
struct WorktreeAnnotationSubjectMigrationTests {
    @Test("subject migration backfills Git subjects and leaves every other annotation byte identical")
    func subjectMigrationBackfillsGitSubjectsAndPreservesHistory() throws {
        // Arrange: a populated v016 database with review and file sessions and output history.
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrator.migrate(databaseQueue, upTo: "016_create_bridge_navigation_schema")
        let fixture = try seedSubjectMigrationFixture(in: databaseQueue)
        let historyBefore = try annotationHistoryRows(in: databaseQueue)
        let sessionsBefore = try sessionRowsWithoutSubjectColumns(in: databaseQueue)

        // Act
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        // Assert: threads, messages, drafts and output attempts (snapshot JSON and exact bytes) are untouched.
        #expect(try annotationHistoryRows(in: databaseQueue) == historyBefore)
        #expect(try sessionRowsWithoutSubjectColumns(in: databaseQueue) == sessionsBefore)
        try databaseQueue.read { database in
            let subjectColumns = try Row.fetchAll(
                database,
                sql: "SELECT subject_kind, local_document_path FROM annotation_session ORDER BY id"
            )
            #expect(subjectColumns.map { $0["subject_kind"] as String } == ["git", "git"])
            #expect(subjectColumns.allSatisfy { ($0["local_document_path"] as String?) == nil })
            #expect(
                try indexColumns("idx_annotation_session_local_document", in: database)
                    == ["subject_kind", "local_document_path", "lifecycle"]
            )
            #expect(
                try indexColumns("idx_annotation_session_worktree", in: database)
                    == ["worktree_id", "lifecycle", "source_relationship"]
            )
            #expect(
                try indexColumns("idx_annotation_session_repository_lifecycle_relationship", in: database)
                    == ["repository_id", "lifecycle", "source_relationship"]
            )
        }

        // Assert: the repository reads each migrated session back under its Git subject and fingerprint.
        let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
        let reviewSessions = try repository.discoverSessions(subject: fixture.reviewFingerprint.subject)
        let fileSessions = try repository.discoverSessions(subject: fixture.fileFingerprint.subject)
        #expect(reviewSessions.map(\.id.rawValue) == [fixture.reviewSessionID])
        #expect(reviewSessions.first?.acceptedSourceFingerprint == fixture.reviewFingerprint)
        #expect(fileSessions.map(\.id.rawValue) == [fixture.fileSessionID])
        #expect(fileSessions.first?.acceptedSourceFingerprint == fixture.fileFingerprint)
        let reviewDetail = try repository.fetchSessionDetail(sessionID: .init(rawValue: fixture.reviewSessionID))
        #expect(reviewDetail.session.subject == fixture.reviewFingerprint.subject)
        #expect(reviewDetail.threads.map(\.messages.count) == [1])
    }

    @Test("a fingerprint that is not JSON is kept verbatim and still fails closed when read")
    func malformedFingerprintIsKeptVerbatimAndFailsClosed() throws {
        // Arrange
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrator.migrate(databaseQueue, upTo: "016_create_bridge_navigation_schema")
        let sessionID = UUIDv7.generate()
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO annotation_session(
                        id, repository_id, worktree_id, lifecycle, source_relationship,
                        accepted_source_fingerprint_json, semantic_revision, created_at, updated_at
                    ) VALUES (?, 'repo-1', 'worktree-1', 'living', 'applicable', 'not json', 1, 1, 1)
                    """,
                arguments: [sessionID.uuidString.lowercased()]
            )
        }

        // Act
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        // Assert
        let storedFingerprint = try databaseQueue.read { database in
            try String.fetchOne(database, sql: "SELECT accepted_source_fingerprint_json FROM annotation_session")
        }
        #expect(storedFingerprint == "not json")
        let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
        #expect(throws: DecodingError.self) {
            try repository.fetchSessionDetail(sessionID: .init(rawValue: sessionID))
        }
    }

    @Test("a subject migration that fails leaves the v016 annotation rows and ledger intact")
    func failedSubjectMigrationLeavesDataIntact() throws {
        // Arrange: history plus a thread whose session is missing, which the deferred foreign-key check refuses.
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrator.migrate(databaseQueue, upTo: "016_create_bridge_navigation_schema")
        _ = try seedSubjectMigrationFixture(in: databaseQueue)
        try databaseQueue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA foreign_keys = OFF")
            try database.execute(
                sql: """
                    INSERT INTO annotation_thread(
                        id, session_id, scope, resolution, origin_json, created_ordinal,
                        semantic_revision, created_at, updated_at, resolved_at
                    ) VALUES (?, ?, 'session', 'open', '{"session":{}}', 0, 1, 1, 1, NULL)
                    """,
                arguments: [UUIDv7.generate().uuidString.lowercased(), UUIDv7.generate().uuidString.lowercased()]
            )
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let historyBefore = try annotationHistoryRows(in: databaseQueue)
        let sessionsBefore = try allRows(of: "annotation_session", in: databaseQueue)

        // Act
        #expect(throws: DatabaseError.self) {
            try WorkspaceLocalMigrations.migrate(databaseQueue)
        }

        // Assert
        #expect(try annotationHistoryRows(in: databaseQueue) == historyBefore)
        #expect(try allRows(of: "annotation_session", in: databaseQueue) == sessionsBefore)
        try databaseQueue.read { database in
            let appliedMigrations = try WorkspaceLocalMigrations.migrator.appliedIdentifiers(database)
            #expect(appliedMigrations.contains("016_create_bridge_navigation_schema"))
            #expect(!appliedMigrations.contains("017_annotation_subject_variants"))
            let sessionColumns = try Row.fetchAll(database, sql: "PRAGMA table_info(annotation_session)")
                .map { $0["name"] as String }
            #expect(!sessionColumns.contains("subject_kind"))
        }
    }
}

private struct SubjectMigrationFixture {
    let reviewSessionID: UUID
    let fileSessionID: UUID
    let reviewFingerprint: WorktreeAnnotationSourceFingerprint
    let fileFingerprint: WorktreeAnnotationSourceFingerprint
}

/// Seeds sessions whose fingerprints carry the pre-017 shape: the repository
/// and worktree identity at the top level instead of a nested subject.
private func seedSubjectMigrationFixture(in databaseQueue: DatabaseQueue) throws -> SubjectMigrationFixture {
    let reviewSessionID = UUIDv7.generate()
    let fileSessionID = UUIDv7.generate()
    let threadID = UUIDv7.generate().uuidString.lowercased()
    let messageID = UUIDv7.generate().uuidString.lowercased()
    let outputAttemptID = UUIDv7.generate().uuidString.lowercased()
    let reviewFingerprint = WorktreeAnnotationSourceFingerprint(
        subject: .git(repositoryID: "repo-1", worktreeID: "worktree-a"),
        fileSourceIdentity: "file-source",
        reviewComparisonOrigin: .init(
            symbolicTarget: "main",
            resolvedTargetOID: String(repeating: "2", count: 40),
            reviewedHeadOID: String(repeating: "1", count: 40),
            baseRole: "merge_base",
            baseOID: String(repeating: "3", count: 40)
        )
    )
    let fileFingerprint = WorktreeAnnotationSourceFingerprint(
        subject: .git(repositoryID: "repo-1", worktreeID: "worktree-b"),
        fileSourceIdentity: "file-only",
        reviewComparisonOrigin: nil
    )

    try databaseQueue.write { database in
        try database.execute(
            sql: """
                INSERT INTO annotation_session(
                    id, repository_id, worktree_id, lifecycle, source_relationship,
                    accepted_source_fingerprint_json, semantic_revision, created_at, updated_at, completed_at
                ) VALUES
                    (?, 'repo-1', 'worktree-a', 'living', 'applicable', ?, 7, 1, 2, NULL),
                    (?, 'repo-1', 'worktree-b', 'living', 'uncertain', ?, 3, 3, 4, NULL)
                """,
            arguments: [
                reviewSessionID.uuidString.lowercased(), try legacyFingerprintJSON(reviewFingerprint),
                fileSessionID.uuidString.lowercased(), try legacyFingerprintJSON(fileFingerprint),
            ]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_thread(
                    id, session_id, scope, resolution, origin_json, created_ordinal,
                    semantic_revision, created_at, updated_at, resolved_at
                ) VALUES (?, ?, 'session', 'open', '{"session":{}}', 0, 5, 1, 2, NULL)
                """,
            arguments: [threadID, reviewSessionID.uuidString.lowercased()]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_message(
                    id, thread_id, ordinal, author_kind, saved_body, saved_body_utf8_bytes,
                    saved_revision, status, semantic_revision, created_at, updated_at, handled,
                    viewed_saved_revision
                ) VALUES (?, ?, 0, 'human', 'saved body', 10, 4, 'editable', 6, 1, 2, 1, NULL)
                """,
            arguments: [messageID, threadID]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_message_draft(
                    message_id, active_edit_token, body, body_utf8_bytes, draft_revision, updated_at
                ) VALUES (?, 'token', 'draft body', 10, 8, 2)
                """,
            arguments: [messageID]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_output_attempt(
                    id, session_id, output_kind, state, format_version, content_type,
                    snapshot_json, exact_bytes, destination_path, repeated_from_attempt_id,
                    effect_error, cleanup_error, created_at, updated_at
                ) VALUES (?, ?, 'clipboard_markdown', 'succeeded', 2, 'text/markdown',
                    '{"session":{"repositoryID":"repo-1","worktreeID":"worktree-a"}}', X'2320526576696577', NULL, NULL,
                    NULL, NULL, 1, 2)
                """,
            arguments: [outputAttemptID, reviewSessionID.uuidString.lowercased()]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_output_attempt_message(
                    attempt_id, message_id, expected_saved_revision, batch_ordinal
                ) VALUES (?, ?, 4, 0)
                """,
            arguments: [outputAttemptID, messageID]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_output_event(id, attempt_id, event_kind, created_at)
                VALUES (?, ?, 'copied', 2)
                """,
            arguments: [UUIDv7.generate().uuidString.lowercased(), outputAttemptID]
        )
    }
    return .init(
        reviewSessionID: reviewSessionID,
        fileSessionID: fileSessionID,
        reviewFingerprint: reviewFingerprint,
        fileFingerprint: fileFingerprint
    )
}

private func legacyFingerprintJSON(_ fingerprint: WorktreeAnnotationSourceFingerprint) throws -> String {
    guard case .git(let repositoryID, let worktreeID) = fingerprint.subject else {
        throw WorktreeAnnotationRepositoryError.invalidState
    }
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(fingerprint)) as? [String: Any]
    )
    object.removeValue(forKey: "subject")
    object["repositoryID"] = repositoryID
    object["worktreeID"] = worktreeID
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try #require(String(bytes: data, encoding: .utf8))
}

private func annotationHistoryRows(in databaseQueue: DatabaseQueue) throws -> [String: [[DatabaseValue]]] {
    let tables = [
        "annotation_thread",
        "annotation_message",
        "annotation_message_draft",
        "annotation_output_attempt",
        "annotation_output_attempt_message",
        "annotation_output_event",
    ]
    return try Dictionary(uniqueKeysWithValues: tables.map { ($0, try allRows(of: $0, in: databaseQueue)) })
}

private func allRows(of table: String, in databaseQueue: DatabaseQueue) throws -> [[DatabaseValue]] {
    try databaseQueue.read { database in
        try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY rowid").map { Array($0.databaseValues) }
    }
}

/// Session columns that exist on both sides of the migration, except the
/// fingerprint the migration rewrites.
private func sessionRowsWithoutSubjectColumns(in databaseQueue: DatabaseQueue) throws -> [[DatabaseValue]] {
    try databaseQueue.read { database in
        try Row.fetchAll(
            database,
            sql: """
                SELECT id, repository_id, worktree_id, lifecycle, source_relationship,
                       accepted_reviewed_subject_json, semantic_revision, created_at, updated_at, completed_at
                FROM annotation_session
                ORDER BY id
                """
        ).map { Array($0.databaseValues) }
    }
}

private func indexColumns(_ index: String, in database: Database) throws -> [String] {
    try Row.fetchAll(database, sql: "PRAGMA index_info(\(index))").map { $0["name"] as String }
}
