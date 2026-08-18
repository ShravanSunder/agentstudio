import Foundation
import GRDB

extension WorktreeAnnotationSQLiteRepository {
    func fetchOutputCandidates(
        sessionID: WorktreeAnnotationSessionID,
        expectedSessionRevision: Int,
        cursor: WorktreeAnnotationOutputCandidateCursor?,
        limit: Int
    ) throws -> WorktreeAnnotationRepositoryOutputCandidatePage {
        guard expectedSessionRevision >= 0, (1...16).contains(limit) else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        return try databaseWriter.read { database in
            guard
                let sessionRevision = try Int.fetchOne(
                    database,
                    sql: "SELECT semantic_revision FROM annotation_session WHERE id = ?",
                    arguments: [sessionID.databaseValue]
                )
            else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            guard sessionRevision == expectedSessionRevision else {
                throw WorktreeAnnotationRepositoryError.conflict(currentRevision: sessionRevision)
            }
            let eligibleMessageCount =
                try Int.fetchOne(
                    database,
                    sql: Self.eligibleOutputCandidateCountSQL,
                    arguments: [
                        sessionID.databaseValue,
                        WorktreeAnnotationMessageStatus.editable.rawValue,
                    ]
                ) ?? 0
            let rows = try Row.fetchAll(
                database,
                sql: Self.outputCandidatePageSQL,
                arguments: [
                    sessionID.databaseValue,
                    WorktreeAnnotationMessageStatus.editable.rawValue,
                    cursor?.flatOrdinal ?? -1,
                    cursor?.flatOrdinal ?? -1,
                    cursor?.messageID.databaseValue ?? "",
                    limit + 1,
                ]
            )
            let decoded = try rows.map(decodeOutputCandidate)
            let visible = Array(decoded.prefix(limit))
            let nextCursor =
                decoded.count > limit
                ? visible.last.map {
                    WorktreeAnnotationOutputCandidateCursor(
                        flatOrdinal: $0.flatOrdinal,
                        messageID: $0.messageID
                    )
                } : nil
            return WorktreeAnnotationRepositoryOutputCandidatePage(
                sessionRevision: sessionRevision,
                candidates: visible,
                nextCursor: nextCursor,
                eligibleMessageCount: eligibleMessageCount
            )
        }
    }

    private static let eligibleOutputCandidateCountSQL = """
        SELECT COUNT(*)
        FROM annotation_message message
        JOIN annotation_thread thread ON thread.id = message.thread_id
        WHERE thread.session_id = ?
          AND message.status = ?
          AND message.saved_body IS NOT NULL
          AND message.saved_revision IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM annotation_message_draft draft
              WHERE draft.message_id = message.id
          )
        """

    private static let outputCandidatePageSQL = """
        WITH eligible AS (
            SELECT message.id AS message_id,
                   thread.id AS thread_id,
                   ROW_NUMBER() OVER (
                       ORDER BY thread.created_ordinal ASC, message.ordinal ASC,
                                thread.id ASC, message.id ASC
                   ) - 1 AS flat_ordinal,
                   thread.origin_json AS origin_json,
                   message.created_at AS authored_at,
                   SUBSTR(message.saved_body, 1, 512) AS saved_body_prefix
            FROM annotation_message message
            JOIN annotation_thread thread ON thread.id = message.thread_id
            WHERE thread.session_id = ?
              AND message.status = ?
              AND message.saved_body IS NOT NULL
              AND message.saved_revision IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM annotation_message_draft draft
                  WHERE draft.message_id = message.id
              )
        )
        SELECT * FROM eligible
        WHERE flat_ordinal > ? OR (flat_ordinal = ? AND message_id > ?)
        ORDER BY flat_ordinal ASC, message_id ASC
        LIMIT ?
        """

    private func decodeOutputCandidate(
        _ row: Row
    ) throws -> WorktreeAnnotationRepositoryOutputCandidate {
        let originJSON: String = row["origin_json"]
        let origin = try Self.jsonDecoder.decode(
            WorktreeAnnotationThreadOrigin.self,
            from: Data(originJSON.utf8)
        )
        guard case .located(let locatedOrigin) = origin else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        return WorktreeAnnotationRepositoryOutputCandidate(
            messageID: try decodeIdentity(row["message_id"] as String),
            threadID: try decodeIdentity(row["thread_id"] as String),
            flatOrdinal: row["flat_ordinal"],
            originalPath: locatedOrigin.repositoryRelativePath,
            originalStartLine: locatedOrigin.startLine,
            originalEndLine: locatedOrigin.endLine,
            authoredAt: Date(timeIntervalSince1970: row["authored_at"]),
            savedBodyPrefix: row["saved_body_prefix"]
        )
    }
}
