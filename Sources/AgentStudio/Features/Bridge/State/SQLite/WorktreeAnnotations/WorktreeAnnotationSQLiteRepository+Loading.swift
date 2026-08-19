import Foundation
import GRDB

extension WorktreeAnnotationIdentity {
    var databaseValue: String { rawValue.uuidString.lowercased() }
}

extension WorktreeAnnotationSQLiteRepository {
    static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var jsonDecoder: JSONDecoder { JSONDecoder() }

    static func requireUTF8String(_ data: Data) throws -> String {
        guard let value = String(bytes: data, encoding: .utf8) else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        return value
    }

    static func encodeJSONString<TValue: Encodable>(_ value: TValue) throws -> String {
        try requireUTF8String(jsonEncoder.encode(value))
    }

    func resolveSessionForNewThread(
        _ database: Database,
        props: CreateRootDraftProps
    ) throws -> WorktreeAnnotationSessionID {
        let candidateRows = try Row.fetchAll(
            database,
            sql: """
                SELECT id, source_relationship FROM annotation_session
                WHERE worktree_id = ? AND lifecycle = 'living'
                  AND source_relationship IN ('applicable', 'uncertain')
                ORDER BY created_at ASC, id ASC
                """,
            arguments: [props.worktreeID]
        )
        let candidates = try candidateRows.map { row -> (WorktreeAnnotationSessionID, String) in
            (try decodeIdentity(row["id"] as String), row["source_relationship"])
        }
        let eligibleIDs = candidates.compactMap { $0.1 == "applicable" ? $0.0 : nil }
        let uncertainIDs = candidates.compactMap { $0.1 == "uncertain" ? $0.0 : nil }

        let sessionID: WorktreeAnnotationSessionID
        switch props.admission {
        case .newSession:
            sessionID = try insertSession(database, props: props)
        case .selected(let selectedSessionID):
            try requireWritableSession(database, sessionID: selectedSessionID)
            sessionID = selectedSessionID
            try advanceSession(
                database,
                sessionID: sessionID,
                accepting: props.sourceFingerprint,
                now: props.now
            )
        case .implicitOrSingle:
            if !uncertainIDs.isEmpty {
                throw WorktreeAnnotationRepositoryError.sessionSelectionRequired(
                    .init(
                        reason: .uncertainContinuityChoice,
                        candidateSessionIDs: uncertainIDs
                    )
                )
            }
            switch eligibleIDs.count {
            case 0:
                sessionID = try insertSession(database, props: props)
            case 1:
                sessionID = eligibleIDs[0]
                try advanceSession(
                    database,
                    sessionID: sessionID,
                    accepting: props.sourceFingerprint,
                    now: props.now
                )
            default:
                throw WorktreeAnnotationRepositoryError.sessionSelectionRequired(
                    .init(
                        reason: .applicableSessionChoice,
                        candidateSessionIDs: eligibleIDs
                    )
                )
            }
        }
        return sessionID
    }

    func insertSession(
        _ database: Database,
        props: CreateRootDraftProps
    ) throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID.generate()
        let fingerprintJSON = try Self.encodeJSONString(props.sourceFingerprint)
        try database.execute(
            sql: """
                INSERT INTO annotation_session(
                    id, repository_id, worktree_id, originating_workspace_id,
                    lifecycle, source_relationship, accepted_source_fingerprint_json,
                    semantic_revision, created_at, updated_at, completed_at
                ) VALUES (?, ?, ?, ?, 'living', 'applicable', ?, 1, ?, ?, NULL)
                """,
            arguments: [
                sessionID.databaseValue,
                props.repositoryID,
                props.worktreeID,
                props.originatingWorkspaceID,
                fingerprintJSON,
                props.now.timeIntervalSince1970,
                props.now.timeIntervalSince1970,
            ]
        )
        return sessionID
    }

    struct InsertMessageDraftProps {
        let messageID: WorktreeAnnotationMessageID
        let threadID: WorktreeAnnotationThreadID
        let ordinal: Int
        let body: String
        let editToken: String
        let now: Date
    }

    func insertMessageDraft(_ database: Database, props: InsertMessageDraftProps) throws {
        try database.execute(
            sql: """
                INSERT INTO annotation_message(
                    id, thread_id, ordinal, author_kind, saved_body, saved_body_utf8_bytes,
                    saved_revision, status, semantic_revision, created_at, updated_at
                ) VALUES (?, ?, ?, 'human', NULL, NULL, NULL, 'editable', 0, ?, ?)
                """,
            arguments: [
                props.messageID.databaseValue,
                props.threadID.databaseValue,
                props.ordinal,
                props.now.timeIntervalSince1970,
                props.now.timeIntervalSince1970,
            ]
        )
        try database.execute(
            sql: """
                INSERT INTO annotation_message_draft(
                    message_id, active_edit_token, body, body_utf8_bytes, draft_revision, updated_at
                ) VALUES (?, ?, ?, ?, 0, ?)
                """,
            arguments: [
                props.messageID.databaseValue,
                props.editToken,
                props.body,
                props.body.utf8.count,
                props.now.timeIntervalSince1970,
            ]
        )
    }

    func nextOrdinal(
        _ database: Database,
        table: String,
        ordinalColumn: String,
        ownerColumn: String,
        ownerID: String
    ) throws -> Int {
        try Int.fetchOne(
            database,
            sql: "SELECT COALESCE(MAX(\(ordinalColumn)), -1) + 1 FROM \(table) WHERE \(ownerColumn) = ?",
            arguments: [ownerID]
        ) ?? 0
    }

    func validateSessionRevision(
        _ database: Database,
        sessionID: WorktreeAnnotationSessionID,
        expectedRevision: Int
    ) throws {
        guard
            let currentRevision = try Int.fetchOne(
                database,
                sql: "SELECT semantic_revision FROM annotation_session WHERE id = ?",
                arguments: [sessionID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        guard currentRevision == expectedRevision else {
            throw WorktreeAnnotationRepositoryError.conflict(currentRevision: currentRevision)
        }
    }

    func requireWritableSession(
        _ database: Database,
        sessionID: WorktreeAnnotationSessionID
    ) throws {
        guard
            let session = try Row.fetchOne(
                database,
                sql: "SELECT lifecycle, source_relationship FROM annotation_session WHERE id = ?",
                arguments: [sessionID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        let lifecycle: String = session["lifecycle"]
        let sourceRelationship: String = session["source_relationship"]
        guard lifecycle == WorktreeAnnotationSessionLifecycle.living.rawValue,
            sourceRelationship == WorktreeAnnotationSourceRelationship.applicable.rawValue
        else {
            throw WorktreeAnnotationRepositoryError.sessionReadOnly
        }
    }

    func advanceSession(
        _ database: Database,
        sessionID: WorktreeAnnotationSessionID,
        now: Date
    ) throws {
        try database.execute(
            sql: """
                UPDATE annotation_session
                SET semantic_revision = semantic_revision + 1, updated_at = ?
                WHERE id = ?
                """,
            arguments: [now.timeIntervalSince1970, sessionID.databaseValue]
        )
        guard database.changesCount == 1 else { throw WorktreeAnnotationRepositoryError.notFound }
    }

    func advanceSession(
        _ database: Database,
        sessionID: WorktreeAnnotationSessionID,
        accepting sourceFingerprint: WorktreeAnnotationSourceFingerprint,
        now: Date
    ) throws {
        guard
            let acceptedFingerprintJSON = try String.fetchOne(
                database,
                sql: "SELECT accepted_source_fingerprint_json FROM annotation_session WHERE id = ?",
                arguments: [sessionID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        let acceptedFingerprint = try Self.jsonDecoder.decode(
            WorktreeAnnotationSourceFingerprint.self,
            from: Data(acceptedFingerprintJSON.utf8)
        )
        guard acceptedFingerprint.repositoryID == sourceFingerprint.repositoryID,
            acceptedFingerprint.worktreeID == sourceFingerprint.worktreeID
        else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        let mergedFingerprint = WorktreeAnnotationSourceFingerprint(
            repositoryID: sourceFingerprint.repositoryID,
            worktreeID: sourceFingerprint.worktreeID,
            fileSourceIdentity: sourceFingerprint.fileSourceIdentity
                ?? acceptedFingerprint.fileSourceIdentity,
            reviewComparisonOrigin: sourceFingerprint.reviewComparisonOrigin
                ?? acceptedFingerprint.reviewComparisonOrigin
        )
        try database.execute(
            sql: """
                UPDATE annotation_session
                SET accepted_source_fingerprint_json = ?, semantic_revision = semantic_revision + 1,
                    updated_at = ?
                WHERE id = ?
                """,
            arguments: [
                try Self.encodeJSONString(mergedFingerprint),
                now.timeIntervalSince1970,
                sessionID.databaseValue,
            ]
        )
        guard database.changesCount == 1 else { throw WorktreeAnnotationRepositoryError.notFound }
    }

    func advanceMessageAndSession(
        _ database: Database,
        messageID: WorktreeAnnotationMessageID,
        sessionID: WorktreeAnnotationSessionID,
        now: Date
    ) throws {
        try database.execute(
            sql: """
                UPDATE annotation_message
                SET semantic_revision = semantic_revision + 1, updated_at = ?
                WHERE id = ?
                """,
            arguments: [now.timeIntervalSince1970, messageID.databaseValue]
        )
        guard database.changesCount == 1 else { throw WorktreeAnnotationRepositoryError.notFound }
        try advanceSession(database, sessionID: sessionID, now: now)
    }

    func requireDraft(
        _ database: Database,
        messageID: WorktreeAnnotationMessageID,
        editToken: String,
        expectedDraftRevision: Int
    ) throws -> Row {
        guard
            let draft = try Row.fetchOne(
                database,
                sql: "SELECT * FROM annotation_message_draft WHERE message_id = ?",
                arguments: [messageID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        guard draft["active_edit_token"] as String? == editToken else {
            throw WorktreeAnnotationRepositoryError.editTokenConflict
        }
        let draftRevision: Int = draft["draft_revision"]
        guard draftRevision == expectedDraftRevision else {
            throw WorktreeAnnotationRepositoryError.conflict(currentRevision: draftRevision)
        }
        return draft
    }

    func requireThreadID(
        _ database: Database,
        messageID: WorktreeAnnotationMessageID
    ) throws -> WorktreeAnnotationThreadID {
        guard
            let value = try String.fetchOne(
                database,
                sql: "SELECT thread_id FROM annotation_message WHERE id = ?",
                arguments: [messageID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        return try decodeIdentity(value)
    }

    func ensureMessageEditable(_ database: Database, messageID: WorktreeAnnotationMessageID) throws {
        guard
            let status = try String.fetchOne(
                database,
                sql: "SELECT status FROM annotation_message WHERE id = ?",
                arguments: [messageID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        guard status == WorktreeAnnotationMessageStatus.editable.rawValue else {
            throw WorktreeAnnotationRepositoryError.messageLocked
        }
        let lockCount =
            try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM annotation_output_attempt_message membership
                    JOIN annotation_output_attempt attempt ON attempt.id = membership.attempt_id
                    WHERE membership.message_id = ?
                      AND attempt.state = 'prepared'
                    """,
                arguments: [messageID.databaseValue]
            ) ?? 0
        guard lockCount == 0 else { throw WorktreeAnnotationRepositoryError.messageLocked }
    }

    func loadSessionDetail(
        _ database: Database,
        sessionID: WorktreeAnnotationSessionID
    ) throws -> WorktreeAnnotationSessionDetail {
        guard
            let sessionRow = try Row.fetchOne(
                database,
                sql: "SELECT * FROM annotation_session WHERE id = ?",
                arguments: [sessionID.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        let session = try decodeSession(sessionRow)
        let threadRows = try Row.fetchAll(
            database,
            sql: "SELECT * FROM annotation_thread WHERE session_id = ? ORDER BY created_ordinal ASC",
            arguments: [sessionID.databaseValue]
        )
        let threads = try threadRows.map { threadRow -> WorktreeAnnotationThreadDetail in
            let thread = try decodeThread(threadRow)
            let messageRows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM annotation_message WHERE thread_id = ? ORDER BY ordinal ASC",
                arguments: [thread.id.databaseValue]
            )
            return WorktreeAnnotationThreadDetail(
                thread: thread,
                messages: try messageRows.map { try decodeMessage(database, row: $0) }
            )
        }
        return WorktreeAnnotationSessionDetail(session: session, threads: threads)
    }

    func decodeSession(_ row: Row) throws -> WorktreeAnnotationSession {
        let fingerprintJSON: String = row["accepted_source_fingerprint_json"]
        return try WorktreeAnnotationSession(
            id: decodeIdentity(row["id"] as String),
            repositoryID: row["repository_id"],
            worktreeID: row["worktree_id"],
            originatingWorkspaceID: row["originating_workspace_id"],
            lifecycle: decodeRawValue(row["lifecycle"] as String),
            sourceRelationship: decodeRawValue(row["source_relationship"] as String),
            acceptedSourceFingerprint: Self.jsonDecoder.decode(
                WorktreeAnnotationSourceFingerprint.self,
                from: Data(fingerprintJSON.utf8)
            ),
            semanticRevision: row["semantic_revision"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            completedAt: (row["completed_at"] as Double?).map(Date.init(timeIntervalSince1970:))
        )
    }

    func decodeThread(_ row: Row) throws -> WorktreeAnnotationThread {
        let originJSON: String = row["origin_json"]
        let origin = try Self.jsonDecoder.decode(
            WorktreeAnnotationThreadOrigin.self,
            from: Data(originJSON.utf8)
        )
        let storedScope: WorktreeAnnotationThreadScope = try decodeRawValue(row["scope"] as String)
        guard storedScope == origin.scope else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        return try WorktreeAnnotationThread(
            id: decodeIdentity(row["id"] as String),
            sessionID: decodeIdentity(row["session_id"] as String),
            origin: origin,
            resolution: decodeRawValue(row["resolution"] as String),
            createdOrdinal: row["created_ordinal"],
            semanticRevision: row["semantic_revision"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            resolvedAt: (row["resolved_at"] as Double?).map(Date.init(timeIntervalSince1970:))
        )
    }

    func decodeMessage(_ database: Database, row: Row) throws -> WorktreeAnnotationMessage {
        let messageID: WorktreeAnnotationMessageID = try decodeIdentity(row["id"] as String)
        let draftRow = try Row.fetchOne(
            database,
            sql: "SELECT * FROM annotation_message_draft WHERE message_id = ?",
            arguments: [messageID.databaseValue]
        )
        let authorKind: String = row["author_kind"]
        guard authorKind == "human" else { throw WorktreeAnnotationRepositoryError.invalidState }
        let savedBody: String? = row["saved_body"]
        let savedRevision: Int? = row["saved_revision"]
        guard (savedBody == nil) == (savedRevision == nil), savedRevision.map({ $0 > 0 }) ?? true else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        if let savedBody { _ = try WorktreeAnnotationMessagePolicy.validate(savedBody) }
        let draft = try draftRow.map { draftRow in
            let body: String = draftRow["body"]
            if savedBody == nil { _ = try WorktreeAnnotationMessagePolicy.validate(body) }
            guard body.utf8.count <= 16_384 else { throw WorktreeAnnotationRepositoryError.invalidState }
            return WorktreeAnnotationDraft(
                messageID: messageID,
                activeEditToken: draftRow["active_edit_token"],
                body: body,
                draftRevision: draftRow["draft_revision"],
                updatedAt: Date(timeIntervalSince1970: draftRow["updated_at"])
            )
        }
        guard savedBody != nil || draft != nil else { throw WorktreeAnnotationRepositoryError.invalidState }
        return try WorktreeAnnotationMessage(
            id: messageID,
            threadID: decodeIdentity(row["thread_id"] as String),
            ordinal: row["ordinal"],
            semanticRevision: row["semantic_revision"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            savedBody: savedBody,
            savedRevision: savedRevision,
            draft: draft,
            status: decodeRawValue(row["status"] as String)
        )
    }

    func decodeIdentity<TIdentityScope>(_ value: String) throws -> WorktreeAnnotationIdentity<TIdentityScope> {
        guard let uuid = UUID(uuidString: value) else { throw WorktreeAnnotationRepositoryError.invalidState }
        return WorktreeAnnotationIdentity(rawValue: uuid)
    }

    func decodeRawValue<TValue: RawRepresentable>(_ value: String) throws -> TValue where TValue.RawValue == String {
        guard let decoded = TValue(rawValue: value) else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        return decoded
    }
}
