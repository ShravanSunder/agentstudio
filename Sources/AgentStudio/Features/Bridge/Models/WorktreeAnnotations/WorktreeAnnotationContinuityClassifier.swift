import Foundation

enum WorktreeAnnotationAncestryDisposition: Equatable, Sendable {
    case notEvaluated
    case exact
    case atLeastLimit
    case traversalLimitReached
    case unrelated
    case readFailure
}

struct WorktreeAnnotationReviewedSubjectContext: Equatable, Sendable {
    let repositoryID: String?
    let worktreeID: String?
    let reviewedSubject: WorktreeAnnotationReviewedSubjectEvidence?
}

enum WorktreeAnnotationContinuityClassification: Equatable, Sendable {
    case applicableSameWorktree
    case applicableTransfer
    case uncertain
    case detached
}

enum WorktreeAnnotationContinuityClassifier {
    static func classify(
        accepted: WorktreeAnnotationReviewedSubjectContext,
        current: WorktreeAnnotationReviewedSubjectContext,
        ancestry: WorktreeAnnotationAncestryDisposition
    ) -> WorktreeAnnotationContinuityClassification {
        guard let acceptedRepositoryID = nonempty(accepted.repositoryID),
            let currentRepositoryID = nonempty(current.repositoryID)
        else {
            return .uncertain
        }
        guard acceptedRepositoryID == currentRepositoryID else { return .detached }

        if let acceptedWorktreeID = nonempty(accepted.worktreeID),
            acceptedWorktreeID == nonempty(current.worktreeID)
        {
            return .applicableSameWorktree
        }

        guard let acceptedEvidence = accepted.reviewedSubject,
            let currentEvidence = current.reviewedSubject,
            let acceptedBranchName = acceptedEvidence.branchName,
            !acceptedBranchName.isEmpty,
            acceptedBranchName == currentEvidence.branchName,
            acceptedEvidence.reviewedHeadOID != nil,
            currentEvidence.reviewedHeadOID != nil,
            ancestry == .exact
        else {
            return .uncertain
        }
        return .applicableTransfer
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
