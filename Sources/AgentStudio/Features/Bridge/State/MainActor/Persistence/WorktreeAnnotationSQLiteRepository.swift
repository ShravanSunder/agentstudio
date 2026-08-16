import Foundation
import GRDB

struct WorktreeAnnotationSQLiteRepository {
    enum SessionAdmission: Equatable, Sendable {
        case implicitOrSingle
        case selected(WorktreeAnnotationSessionID)
        case newSession
    }

    struct CreateRootDraftProps: Sendable {
        let admission: SessionAdmission
        let repositoryID: String
        let worktreeID: String
        let originatingWorkspaceID: String?
        let sourceFingerprint: WorktreeAnnotationSourceFingerprint
        let origin: WorktreeAnnotationThreadOrigin
        let body: String
        let editToken: String
        let now: Date
    }

    struct FlushDraftProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let messageID: WorktreeAnnotationMessageID
        let editToken: String
        let expectedSessionRevision: Int
        let expectedDraftRevision: Int?
        let body: String
        let now: Date
    }

    struct SaveDraftProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let messageID: WorktreeAnnotationMessageID
        let editToken: String
        let expectedSessionRevision: Int
        let expectedDraftRevision: Int
        let now: Date
    }

    struct RevertDraftProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let messageID: WorktreeAnnotationMessageID
        let editToken: String
        let expectedSessionRevision: Int
        let expectedDraftRevision: Int
        let now: Date
    }

    struct CreateReplyDraftProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let threadID: WorktreeAnnotationThreadID
        let expectedSessionRevision: Int
        let body: String
        let editToken: String
        let now: Date
    }

    struct SetThreadResolutionProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let threadID: WorktreeAnnotationThreadID
        let resolution: WorktreeAnnotationThreadResolution
        let expectedSessionRevision: Int
        let now: Date
    }

    struct SetSessionLifecycleProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let lifecycle: WorktreeAnnotationSessionLifecycle
        let expectedSessionRevision: Int
        let expectedOpenThreadCount: Int
        let confirmsUnresolvedWork: Bool
        let now: Date
    }

    struct SetSourceRelationshipProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let relationship: WorktreeAnnotationSourceRelationship
        let sourceFingerprint: WorktreeAnnotationSourceFingerprint?
        let expectedSessionRevision: Int
        let now: Date
    }

    let databaseWriter: any DatabaseWriter

    func discoverSessions(worktreeID: String) throws -> [WorktreeAnnotationSession] {
        try databaseWriter.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM annotation_session
                    WHERE worktree_id = ?
                    ORDER BY created_at ASC, id ASC
                    """,
                arguments: [worktreeID]
            ).map(decodeSession)
        }
    }

    func fetchSessionDetail(sessionID: WorktreeAnnotationSessionID) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.read { database in
            try loadSessionDetail(database, sessionID: sessionID)
        }
    }

    func createRootDraft(_ props: CreateRootDraftProps) throws -> WorktreeAnnotationSessionDetail {
        let body = try WorktreeAnnotationMessagePolicy.validate(props.body)
        return try databaseWriter.write { database in
            let sessionID = try resolveSessionForNewThread(database, props: props)
            let threadID = WorktreeAnnotationThreadID.generate()
            let messageID = WorktreeAnnotationMessageID.generate()
            let threadOrdinal = try nextOrdinal(
                database,
                table: "annotation_thread",
                ordinalColumn: "created_ordinal",
                ownerColumn: "session_id",
                ownerID: sessionID.databaseValue
            )
            let encodedOrigin = try Self.encodeJSONString(props.origin)

            try database.execute(
                sql: """
                    INSERT INTO annotation_thread(
                        id, session_id, scope, resolution, origin_json, created_ordinal,
                        semantic_revision, created_at, updated_at, resolved_at
                    ) VALUES (?, ?, ?, 'open', ?, ?, 0, ?, ?, NULL)
                    """,
                arguments: [
                    threadID.databaseValue,
                    sessionID.databaseValue,
                    props.origin.scope.rawValue,
                    encodedOrigin,
                    threadOrdinal,
                    props.now.timeIntervalSince1970,
                    props.now.timeIntervalSince1970,
                ]
            )
            try insertMessageDraft(
                database,
                props: .init(
                    messageID: messageID,
                    threadID: threadID,
                    ordinal: 0,
                    body: body,
                    editToken: props.editToken,
                    now: props.now
                )
            )
            return try loadSessionDetail(database, sessionID: sessionID)
        }
    }

    func flushDraft(_ props: FlushDraftProps) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            try ensureMessageEditable(database, messageID: props.messageID)
            let savedBody = try String.fetchOne(
                database,
                sql: "SELECT saved_body FROM annotation_message WHERE id = ?",
                arguments: [props.messageID.databaseValue]
            )
            let body: String
            if props.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard savedBody != nil,
                    props.body.utf8.count <= WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes
                else {
                    throw WorktreeAnnotationRepositoryError.invalidState
                }
                body = props.body
            } else {
                body = try WorktreeAnnotationMessagePolicy.validate(props.body)
            }
            let existingDraft = try Row.fetchOne(
                database,
                sql: "SELECT active_edit_token, draft_revision FROM annotation_message_draft WHERE message_id = ?",
                arguments: [props.messageID.databaseValue]
            )
            let nextDraftRevision: Int
            if let existingDraft {
                let editToken: String? = existingDraft["active_edit_token"]
                let draftRevision: Int = existingDraft["draft_revision"]
                guard editToken == props.editToken else {
                    throw WorktreeAnnotationRepositoryError.editTokenConflict
                }
                guard props.expectedDraftRevision == draftRevision else {
                    throw WorktreeAnnotationRepositoryError.conflict(currentRevision: draftRevision)
                }
                nextDraftRevision = draftRevision + 1
            } else {
                guard props.expectedDraftRevision == nil else {
                    throw WorktreeAnnotationRepositoryError.conflict(currentRevision: 0)
                }
                nextDraftRevision = 0
            }

            try database.execute(
                sql: """
                    INSERT INTO annotation_message_draft(
                        message_id, active_edit_token, body, body_utf8_bytes, draft_revision, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(message_id) DO UPDATE SET
                        body = excluded.body,
                        body_utf8_bytes = excluded.body_utf8_bytes,
                        draft_revision = excluded.draft_revision,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    props.messageID.databaseValue,
                    props.editToken,
                    body,
                    body.utf8.count,
                    nextDraftRevision,
                    props.now.timeIntervalSince1970,
                ]
            )
            try advanceMessageAndSession(
                database,
                messageID: props.messageID,
                sessionID: props.sessionID,
                now: props.now
            )
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }

    func saveDraft(_ props: SaveDraftProps) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            try ensureMessageEditable(database, messageID: props.messageID)
            let draft = try requireDraft(
                database,
                messageID: props.messageID,
                editToken: props.editToken,
                expectedDraftRevision: props.expectedDraftRevision
            )
            let body = try WorktreeAnnotationMessagePolicy.validate(draft["body"] as String)
            try database.execute(
                sql: """
                    UPDATE annotation_message
                    SET saved_body = ?, saved_body_utf8_bytes = ?,
                        saved_revision = COALESCE(saved_revision, 0) + 1
                    WHERE id = ?
                    """,
                arguments: [
                    body,
                    body.utf8.count,
                    props.messageID.databaseValue,
                ]
            )
            guard database.changesCount == 1 else { throw WorktreeAnnotationRepositoryError.notFound }
            try database.execute(
                sql: "DELETE FROM annotation_message_draft WHERE message_id = ?",
                arguments: [props.messageID.databaseValue]
            )
            try advanceMessageAndSession(
                database,
                messageID: props.messageID,
                sessionID: props.sessionID,
                now: props.now
            )
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }

    func revertDraft(_ props: RevertDraftProps) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            try ensureMessageEditable(database, messageID: props.messageID)
            _ = try requireDraft(
                database,
                messageID: props.messageID,
                editToken: props.editToken,
                expectedDraftRevision: props.expectedDraftRevision
            )
            let hasSavedBody =
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM annotation_message WHERE id = ? AND saved_body IS NOT NULL",
                    arguments: [props.messageID.databaseValue]
                ) == 1
            if !hasSavedBody {
                let threadID = try requireThreadID(database, messageID: props.messageID)
                try database.execute(
                    sql: "DELETE FROM annotation_message WHERE id = ?",
                    arguments: [props.messageID.databaseValue]
                )
                let remainingMessageCount =
                    try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM annotation_message WHERE thread_id = ?",
                        arguments: [threadID.databaseValue]
                    ) ?? 0
                if remainingMessageCount == 0 {
                    try database.execute(
                        sql: "DELETE FROM annotation_thread WHERE id = ?",
                        arguments: [threadID.databaseValue]
                    )
                }
                try advanceSession(database, sessionID: props.sessionID, now: props.now)
            } else {
                try database.execute(
                    sql: "DELETE FROM annotation_message_draft WHERE message_id = ?",
                    arguments: [props.messageID.databaseValue]
                )
                try advanceMessageAndSession(
                    database,
                    messageID: props.messageID,
                    sessionID: props.sessionID,
                    now: props.now
                )
            }
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }

    func createReplyDraft(_ props: CreateReplyDraftProps) throws -> WorktreeAnnotationSessionDetail {
        let body = try WorktreeAnnotationMessagePolicy.validate(props.body)
        return try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            let resolution = try String.fetchOne(
                database,
                sql: "SELECT resolution FROM annotation_thread WHERE id = ? AND session_id = ?",
                arguments: [props.threadID.databaseValue, props.sessionID.databaseValue]
            )
            guard resolution != nil else { throw WorktreeAnnotationRepositoryError.notFound }
            guard resolution == WorktreeAnnotationThreadResolution.open.rawValue else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            let messageID = WorktreeAnnotationMessageID.generate()
            let ordinal = try nextOrdinal(
                database,
                table: "annotation_message",
                ordinalColumn: "ordinal",
                ownerColumn: "thread_id",
                ownerID: props.threadID.databaseValue
            )
            try insertMessageDraft(
                database,
                props: .init(
                    messageID: messageID,
                    threadID: props.threadID,
                    ordinal: ordinal,
                    body: body,
                    editToken: props.editToken,
                    now: props.now
                )
            )
            try database.execute(
                sql:
                    "UPDATE annotation_thread SET semantic_revision = semantic_revision + 1, updated_at = ? WHERE id = ?",
                arguments: [props.now.timeIntervalSince1970, props.threadID.databaseValue]
            )
            try advanceSession(database, sessionID: props.sessionID, now: props.now)
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }

    func setThreadResolution(_ props: SetThreadResolutionProps) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            guard
                let currentResolution = try String.fetchOne(
                    database,
                    sql: "SELECT resolution FROM annotation_thread WHERE id = ? AND session_id = ?",
                    arguments: [props.threadID.databaseValue, props.sessionID.databaseValue]
                )
            else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            if currentResolution == props.resolution.rawValue {
                return try loadSessionDetail(database, sessionID: props.sessionID)
            }
            try database.execute(
                sql: """
                    UPDATE annotation_thread
                    SET resolution = ?, semantic_revision = semantic_revision + 1,
                        updated_at = ?, resolved_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    props.resolution.rawValue,
                    props.now.timeIntervalSince1970,
                    props.resolution == .resolved ? props.now.timeIntervalSince1970 : nil,
                    props.threadID.databaseValue,
                ]
            )
            try advanceSession(database, sessionID: props.sessionID, now: props.now)
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }
}
