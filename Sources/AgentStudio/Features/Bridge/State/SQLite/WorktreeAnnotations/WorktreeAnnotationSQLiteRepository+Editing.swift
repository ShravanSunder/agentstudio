import Foundation
import GRDB

extension WorktreeAnnotationSQLiteRepository {
    func acquireEditToken(_ props: AcquireEditTokenProps) throws
        -> WorktreeAnnotationCommittedMutation<WorktreeAnnotationSessionDetail>
    {
        try databaseWriter.write { database in
            try validateMessageRevision(
                database,
                messageID: props.messageID,
                sessionID: props.sessionID,
                expectedRevision: props.expectedMessageRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            try ensureMessageEditable(database, messageID: props.messageID)
            guard
                let draft = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT active_edit_token, draft_revision
                        FROM annotation_message_draft
                        WHERE message_id = ?
                        """,
                    arguments: [props.messageID.databaseValue]
                )
            else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            let currentToken: String? = draft["active_edit_token"]
            let currentRevision: Int = draft["draft_revision"]
            guard currentRevision == props.expectedDraftRevision else {
                throw WorktreeAnnotationRepositoryError.conflict(currentRevision: currentRevision)
            }
            if currentToken == props.editToken, props.liveEditTokens.contains(props.editToken) {
                return WorktreeAnnotationCommittedMutation(
                    canonicalResult: try loadSessionDetail(database, sessionID: props.sessionID),
                    change: .noChange
                )
            }
            if let currentToken, props.liveEditTokens.contains(currentToken) {
                throw WorktreeAnnotationRepositoryError.editTokenConflict
            }
            guard currentRevision < Int.max else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            try database.execute(
                sql: """
                    UPDATE annotation_message_draft
                    SET active_edit_token = ?, draft_revision = draft_revision + 1, updated_at = ?
                    WHERE message_id = ?
                    """,
                arguments: [
                    props.editToken,
                    props.now.timeIntervalSince1970,
                    props.messageID.databaseValue,
                ]
            )
            try advanceMessageAndSession(
                database,
                messageID: props.messageID,
                sessionID: props.sessionID,
                now: props.now
            )
            let detail = try loadSessionDetail(database, sessionID: props.sessionID)
            return .content(detail)
        }
    }

    func releaseEditToken(_ props: ReleaseEditTokenProps) throws
        -> WorktreeAnnotationCommittedMutation<WorktreeAnnotationSessionDetail>
    {
        try databaseWriter.write { database in
            try validateMessageRevision(
                database,
                messageID: props.messageID,
                sessionID: props.sessionID,
                expectedRevision: props.expectedMessageRevision
            )
            try requireWritableSession(database, sessionID: props.sessionID)
            try ensureMessageEditable(database, messageID: props.messageID)
            let draft = try requireDraft(
                database,
                messageID: props.messageID,
                editToken: props.editToken,
                expectedDraftRevision: props.expectedDraftRevision
            )
            let currentRevision: Int = draft["draft_revision"]
            guard currentRevision < Int.max else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            try database.execute(
                sql: """
                    UPDATE annotation_message_draft
                    SET active_edit_token = NULL, draft_revision = draft_revision + 1, updated_at = ?
                    WHERE message_id = ?
                    """,
                arguments: [props.now.timeIntervalSince1970, props.messageID.databaseValue]
            )
            try advanceMessageAndSession(
                database,
                messageID: props.messageID,
                sessionID: props.sessionID,
                now: props.now
            )
            let detail = try loadSessionDetail(database, sessionID: props.sessionID)
            return .content(detail)
        }
    }
}
