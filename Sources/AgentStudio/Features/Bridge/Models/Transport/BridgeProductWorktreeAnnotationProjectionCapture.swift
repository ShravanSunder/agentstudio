import Foundation

enum BridgeProductAnnotationProjectionRecoveryStatus: String, Codable, Equatable, Sendable {
    case available
    case recoveredDegraded = "recovered_degraded"
    case unavailable
}

struct BridgeProductAnnotationProjectionCapture: Sendable {
    let worktreeID: String
    let recoveryStatus: BridgeProductAnnotationProjectionRecoveryStatus
    let sessions: [WorktreeAnnotationSession]
    let details: [WorktreeAnnotationSessionDetail]
    let placementsByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
    let projectionRevision: Int
    let sourceGeneration: Int

    init(
        worktreeID: String,
        recoveryStatus: BridgeProductAnnotationProjectionRecoveryStatus,
        sessions: [WorktreeAnnotationSession],
        details: [WorktreeAnnotationSessionDetail],
        placementsByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection],
        projectionRevision: Int,
        sourceGeneration: Int
    ) {
        self.worktreeID = worktreeID
        self.recoveryStatus = recoveryStatus
        self.sessions = sessions.sorted(by: annotationProjectionSessionOrdering)
        self.details = details.sorted { lhs, rhs in
            annotationProjectionSessionOrdering(lhs.session, rhs.session)
        }.map { detail in
            WorktreeAnnotationSessionDetail(
                session: detail.session,
                threads: detail.threads.sorted(by: annotationProjectionThreadOrdering).map { threadDetail in
                    WorktreeAnnotationThreadDetail(
                        thread: threadDetail.thread,
                        messages: threadDetail.messages.sorted(by: annotationProjectionMessageOrdering)
                    )
                }
            )
        }
        self.placementsByThreadID = placementsByThreadID
        self.projectionRevision = projectionRevision
        self.sourceGeneration = sourceGeneration
    }
}

private func annotationProjectionSessionOrdering(
    _ lhs: WorktreeAnnotationSession,
    _ rhs: WorktreeAnnotationSession
) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
}

private func annotationProjectionThreadOrdering(
    _ lhs: WorktreeAnnotationThreadDetail,
    _ rhs: WorktreeAnnotationThreadDetail
) -> Bool {
    if lhs.thread.createdOrdinal != rhs.thread.createdOrdinal {
        return lhs.thread.createdOrdinal < rhs.thread.createdOrdinal
    }
    return lhs.thread.id.rawValue.uuidString < rhs.thread.id.rawValue.uuidString
}

private func annotationProjectionMessageOrdering(
    _ lhs: WorktreeAnnotationMessage,
    _ rhs: WorktreeAnnotationMessage
) -> Bool {
    if lhs.ordinal != rhs.ordinal { return lhs.ordinal < rhs.ordinal }
    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
}
