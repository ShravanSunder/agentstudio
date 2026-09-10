struct WorktreeAnnotationRemovedMessage: Equatable, Sendable {
    let messageID: WorktreeAnnotationMessageID
    let threadID: WorktreeAnnotationThreadID
    let messageRevision: Int
}

/// Retains deletion identity from the transaction even when the returned detail has no row.
struct WorktreeAnnotationDraftMutationResult: Equatable, Sendable {
    let detail: WorktreeAnnotationSessionDetail
    let removedMessage: WorktreeAnnotationRemovedMessage?
}

extension WorktreeAnnotationCommittedMutation where CanonicalResult == WorktreeAnnotationDraftMutationResult {
    static func content(_ detail: WorktreeAnnotationSessionDetail) -> Self {
        let committed = WorktreeAnnotationCommittedMutation<WorktreeAnnotationSessionDetail>.content(detail)
        return Self(canonicalResult: .init(detail: detail, removedMessage: nil), change: committed.change)
    }

    static func catalog(
        _ detail: WorktreeAnnotationSessionDetail, removedMessage: WorktreeAnnotationRemovedMessage
    ) -> Self {
        let committed = WorktreeAnnotationCommittedMutation<WorktreeAnnotationSessionDetail>.catalog(detail)
        return Self(canonicalResult: .init(detail: detail, removedMessage: removedMessage), change: committed.change)
    }
}
