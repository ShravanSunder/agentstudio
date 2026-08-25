import Foundation
import GRDB

extension WorktreeAnnotationSQLiteRepository {
    struct ViewedItem: Equatable, Hashable, Sendable {
        let messageID: WorktreeAnnotationMessageID
        let expectedSavedRevision: Int
    }

    struct MarkMessagesViewedProps: Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let items: [ViewedItem]
        let now: Date
    }

    struct ViewedMutationResult: Equatable, Sendable {
        let changed: Bool
        let results: [WorktreeAnnotationViewedResult]
        let sessionID: WorktreeAnnotationSessionID
        let worktreeID: String
    }

    func markMessagesViewed(_ props: MarkMessagesViewedProps) throws -> ViewedMutationResult {
        guard (1...256).contains(props.items.count), Set(props.items).count == props.items.count,
            props.items.allSatisfy({ $0.expectedSavedRevision > 0 })
        else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        return try databaseWriter.write { database in
            guard
                let sessionRow = try Row.fetchOne(
                    database,
                    sql: "SELECT semantic_revision, worktree_id FROM annotation_session WHERE id = ?",
                    arguments: [props.sessionID.databaseValue]
                )
            else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            let currentSessionRevision: Int = sessionRow["semantic_revision"]
            let worktreeID: String = sessionRow["worktree_id"]
            var evaluations: [ViewedItemEvaluation] = []
            evaluations.reserveCapacity(props.items.count)
            var changedMessageIDs: [WorktreeAnnotationMessageID] = []

            for item in props.items {
                guard
                    let messageRow = try Row.fetchOne(
                        database,
                        sql: """
                            SELECT message.author_kind, message.saved_revision,
                                   message.viewed_saved_revision
                            FROM annotation_message AS message
                            JOIN annotation_thread AS thread ON thread.id = message.thread_id
                            WHERE message.id = ? AND thread.session_id = ?
                            """,
                        arguments: [item.messageID.databaseValue, props.sessionID.databaseValue]
                    )
                else {
                    evaluations.append(.notViewed(item: item, disposition: .notFound))
                    continue
                }
                let authorKind: String = messageRow["author_kind"]
                guard authorKind == WorktreeAnnotationAuthorKind.agent.rawValue else {
                    evaluations.append(.notViewed(item: item, disposition: .notAgent))
                    continue
                }
                let savedRevision: Int? = messageRow["saved_revision"]
                guard savedRevision == item.expectedSavedRevision else {
                    evaluations.append(.notViewed(item: item, disposition: .stale))
                    continue
                }
                let viewedSavedRevision: Int? = messageRow["viewed_saved_revision"]
                if viewedSavedRevision == item.expectedSavedRevision {
                    evaluations.append(.viewed(item: item, disposition: .alreadyViewed))
                    continue
                }
                try database.execute(
                    sql: """
                        UPDATE annotation_message
                        SET viewed_saved_revision = ?, semantic_revision = semantic_revision + 1,
                            updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        item.expectedSavedRevision,
                        props.now.timeIntervalSince1970,
                        item.messageID.databaseValue,
                    ]
                )
                guard database.changesCount == 1 else {
                    throw WorktreeAnnotationRepositoryError.invalidState
                }
                changedMessageIDs.append(item.messageID)
                evaluations.append(.viewed(item: item, disposition: .changed))
            }

            let changed = !changedMessageIDs.isEmpty
            let committedSessionRevision = currentSessionRevision + (changed ? 1 : 0)
            if changed {
                try database.execute(
                    sql: """
                        UPDATE annotation_session
                        SET semantic_revision = semantic_revision + 1, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [props.now.timeIntervalSince1970, props.sessionID.databaseValue]
                )
                guard database.changesCount == 1 else {
                    throw WorktreeAnnotationRepositoryError.invalidState
                }
            }

            return ViewedMutationResult(
                changed: changed,
                results: evaluations.map { $0.result(committedSessionRevision: committedSessionRevision) },
                sessionID: props.sessionID,
                worktreeID: worktreeID
            )
        }
    }
}

private enum ViewedItemEvaluation {
    case viewed(
        item: WorktreeAnnotationSQLiteRepository.ViewedItem,
        disposition: WorktreeAnnotationViewedResult.ViewedDisposition
    )
    case notViewed(
        item: WorktreeAnnotationSQLiteRepository.ViewedItem,
        disposition: WorktreeAnnotationViewedResult.NotViewedDisposition
    )

    func result(committedSessionRevision: Int) -> WorktreeAnnotationViewedResult {
        switch self {
        case .viewed(let item, let disposition):
            .viewed(
                messageID: item.messageID,
                savedRevision: item.expectedSavedRevision,
                committedSessionRevision: committedSessionRevision,
                disposition: disposition
            )
        case .notViewed(let item, let disposition):
            .notViewed(
                messageID: item.messageID,
                expectedSavedRevision: item.expectedSavedRevision,
                disposition: disposition
            )
        }
    }
}
