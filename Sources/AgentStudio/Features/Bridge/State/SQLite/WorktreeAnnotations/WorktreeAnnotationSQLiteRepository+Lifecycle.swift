import Foundation
import GRDB

extension WorktreeAnnotationSQLiteRepository {
    func setSessionLifecycle(_ props: SetSessionLifecycleProps) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            let openThreadCount =
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM annotation_thread WHERE session_id = ? AND resolution = 'open'",
                    arguments: [props.sessionID.databaseValue]
                ) ?? 0
            guard openThreadCount == props.expectedOpenThreadCount else {
                throw WorktreeAnnotationRepositoryError.openThreadCountConflict(currentCount: openThreadCount)
            }
            if props.lifecycle == .completed, openThreadCount > 0, !props.confirmsUnresolvedWork {
                throw WorktreeAnnotationRepositoryError.unresolvedWorkConfirmationRequired
            }
            try database.execute(
                sql: """
                    UPDATE annotation_session
                    SET lifecycle = ?, semantic_revision = semantic_revision + 1,
                        updated_at = ?, completed_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    props.lifecycle.rawValue,
                    props.now.timeIntervalSince1970,
                    props.lifecycle == .completed ? props.now.timeIntervalSince1970 : nil,
                    props.sessionID.databaseValue,
                ]
            )
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }

    func setSourceRelationship(_ props: SetSourceRelationshipProps) throws -> WorktreeAnnotationSessionDetail {
        try databaseWriter.write { database in
            try validateSessionRevision(
                database,
                sessionID: props.sessionID,
                expectedRevision: props.expectedSessionRevision
            )
            let encodedFingerprint: String?
            if let sourceFingerprint = props.sourceFingerprint {
                encodedFingerprint = try Self.encodeJSONString(sourceFingerprint)
            } else {
                encodedFingerprint = nil
            }
            try database.execute(
                sql: """
                    UPDATE annotation_session
                    SET source_relationship = ?,
                        accepted_source_fingerprint_json = COALESCE(?, accepted_source_fingerprint_json),
                        semantic_revision = semantic_revision + 1,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    props.relationship.rawValue,
                    encodedFingerprint,
                    props.now.timeIntervalSince1970,
                    props.sessionID.databaseValue,
                ]
            )
            return try loadSessionDetail(database, sessionID: props.sessionID)
        }
    }

    func acceptCurrentAssociation(
        _ props: AcceptCurrentAssociationProps
    ) throws -> AssociationMutationResult {
        try databaseWriter.write { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: "SELECT repository_id, worktree_id, semantic_revision FROM annotation_session WHERE id = ?",
                    arguments: [props.sessionID.databaseValue]
                )
            else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            let currentRevision: Int = row["semantic_revision"]
            guard currentRevision == props.expectedSessionRevision else {
                throw WorktreeAnnotationRepositoryError.conflict(currentRevision: currentRevision)
            }
            guard row["repository_id"] as String == props.expectedRepositoryID,
                row["worktree_id"] as String == props.previousWorktreeID,
                props.acceptedSourceFingerprint.repositoryID == props.expectedRepositoryID,
                props.acceptedSourceFingerprint.worktreeID == props.currentWorktreeID
            else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            try database.execute(
                sql: """
                    UPDATE annotation_session
                    SET worktree_id = ?, source_relationship = 'applicable',
                        accepted_reviewed_subject_json = ?, accepted_source_fingerprint_json = ?,
                        semantic_revision = semantic_revision + 1, updated_at = ?
                    WHERE id = ? AND semantic_revision = ? AND repository_id = ? AND worktree_id = ?
                    """,
                arguments: [
                    props.currentWorktreeID,
                    try Self.encodeJSONString(props.acceptedReviewedSubject),
                    try Self.encodeJSONString(props.acceptedSourceFingerprint),
                    props.now.timeIntervalSince1970,
                    props.sessionID.databaseValue,
                    props.expectedSessionRevision,
                    props.expectedRepositoryID,
                    props.previousWorktreeID,
                ]
            )
            guard database.changesCount == 1 else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            return AssociationMutationResult(
                detail: try loadSessionDetail(database, sessionID: props.sessionID),
                previousWorktreeID: props.previousWorktreeID,
                currentWorktreeID: props.currentWorktreeID
            )
        }
    }
}
