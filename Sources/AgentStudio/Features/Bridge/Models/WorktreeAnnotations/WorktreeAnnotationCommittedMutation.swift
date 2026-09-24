struct WorktreeAnnotationCommittedMutation<CanonicalResult: Sendable>: Sendable {
    let canonicalResult: CanonicalResult
    let change: WorktreeAnnotationCommittedChange
}

extension WorktreeAnnotationCommittedMutation: Equatable where CanonicalResult: Equatable {}

struct WorktreeAnnotationCommittedSessionChange: Equatable, Sendable {
    let subject: WorktreeAnnotationSubject
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
        subjects: Set<WorktreeAnnotationSubject>,
        reason: WorktreeAnnotationControlChangeReason,
        sessionChanges: [WorktreeAnnotationCommittedSessionChange]
    )
    case catalog(
        subjects: Set<WorktreeAnnotationSubject>,
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
        subjects: Set<WorktreeAnnotationSubject>? = nil
    ) -> Self {
        Self(
            canonicalResult: canonicalResult,
            change: .catalog(
                subjects: subjects ?? [canonicalResult.session.subject],
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
                subjects: [canonicalResult.session.subject],
                reason: reason,
                sessionChanges: [canonicalResult.committedSessionChange]
            )
        )
    }
}

extension WorktreeAnnotationSessionDetail {
    var committedSessionChange: WorktreeAnnotationCommittedSessionChange {
        WorktreeAnnotationCommittedSessionChange(
            subject: session.subject,
            sessionID: session.id,
            semanticRevision: session.semanticRevision
        )
    }
}
