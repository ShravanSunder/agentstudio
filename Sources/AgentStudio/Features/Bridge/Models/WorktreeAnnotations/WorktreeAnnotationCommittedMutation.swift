struct WorktreeAnnotationCommittedMutation<CanonicalResult: Sendable>: Sendable {
    let canonicalResult: CanonicalResult
    let change: WorktreeAnnotationCommittedChange
}

extension WorktreeAnnotationCommittedMutation: Equatable where CanonicalResult: Equatable {}

struct WorktreeAnnotationCommittedSessionChange: Equatable, Sendable {
    let worktreeID: String
    let sessionID: WorktreeAnnotationSessionID
    let semanticRevision: Int
}

enum WorktreeAnnotationControlChangeReason: Equatable, Sendable {
    case discovery
    case recovery
}

enum WorktreeAnnotationCommittedChange: Equatable, Sendable {
    case noChange
    case content(sessionChanges: [WorktreeAnnotationCommittedSessionChange])
    case control(
        worktreeIDs: Set<String>,
        reason: WorktreeAnnotationControlChangeReason,
        sessionChanges: [WorktreeAnnotationCommittedSessionChange]
    )
    case catalog(
        worktreeIDs: Set<String>,
        sessionChanges: [WorktreeAnnotationCommittedSessionChange]
    )
}

extension WorktreeAnnotationCommittedMutation where CanonicalResult == WorktreeAnnotationSessionDetail {
    static func content(_ canonicalResult: CanonicalResult) -> Self {
        Self(
            canonicalResult: canonicalResult,
            change: .content(sessionChanges: [canonicalResult.committedSessionChange])
        )
    }

    static func catalog(
        _ canonicalResult: CanonicalResult,
        worktreeIDs: Set<String>? = nil
    ) -> Self {
        Self(
            canonicalResult: canonicalResult,
            change: .catalog(
                worktreeIDs: worktreeIDs ?? [canonicalResult.session.worktreeID],
                sessionChanges: [canonicalResult.committedSessionChange]
            )
        )
    }

    static func control(
        _ canonicalResult: CanonicalResult,
        reason: WorktreeAnnotationControlChangeReason
    ) -> Self {
        Self(
            canonicalResult: canonicalResult,
            change: .control(
                worktreeIDs: [canonicalResult.session.worktreeID],
                reason: reason,
                sessionChanges: [canonicalResult.committedSessionChange]
            )
        )
    }
}

extension WorktreeAnnotationSessionDetail {
    var committedSessionChange: WorktreeAnnotationCommittedSessionChange {
        WorktreeAnnotationCommittedSessionChange(
            worktreeID: session.worktreeID,
            sessionID: session.id,
            semanticRevision: session.semanticRevision
        )
    }
}
