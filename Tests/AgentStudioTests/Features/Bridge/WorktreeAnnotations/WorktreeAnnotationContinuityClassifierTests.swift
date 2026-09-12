import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation continuity classifier")
struct WorktreeAnnotationContinuityClassifierTests {
    @Test("reviewed subject evidence is strict and permits witness-only migration evidence")
    func reviewedSubjectEvidenceCodecIsStrict() throws {
        let witnessOnly = try WorktreeAnnotationReviewedSubjectEvidence(
            branchName: nil,
            reviewedHeadOID: "1111111111111111111111111111111111111111"
        )
        let encoded = try JSONEncoder().encode(witnessOnly)

        #expect(try JSONDecoder().decode(WorktreeAnnotationReviewedSubjectEvidence.self, from: encoded) == witnessOnly)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                WorktreeAnnotationReviewedSubjectEvidence.self,
                from: Data(#"{"branchName":"feature/review","reviewedHeadOID":"head","unexpected":true}"#.utf8)
            )
        }
        #expect(throws: WorktreeAnnotationSubjectEvidenceError.self) {
            try WorktreeAnnotationReviewedSubjectEvidence(branchName: "", reviewedHeadOID: "head")
        }
        #expect(throws: WorktreeAnnotationSubjectEvidenceError.self) {
            try WorktreeAnnotationReviewedSubjectEvidence(
                branchName: "feature/review",
                reviewedHeadOID: "not-a-full-oid"
            )
        }
        #expect(throws: WorktreeAnnotationSubjectEvidenceError.self) {
            try WorktreeAnnotationReviewedSubjectEvidence(branchName: nil, reviewedHeadOID: nil)
        }
    }

    @Test("ordered classifier distinguishes repository mismatch, same worktree, and proven transfer")
    func orderedContinuityGuards() throws {
        let accepted = try context(repositoryID: "repo", worktreeID: "worktree-a")

        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: try context(repositoryID: "other-repo", worktreeID: "worktree-a"),
                ancestry: .exact
            ) == .detached
        )
        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: try context(
                    repositoryID: "repo",
                    worktreeID: "worktree-a",
                    branchName: "renamed",
                    reviewedHeadOID: "2222222222222222222222222222222222222222"
                ),
                ancestry: .unrelated
            ) == .applicableSameWorktree
        )
        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: try context(repositoryID: "repo", worktreeID: "worktree-b"),
                ancestry: .exact
            ) == .applicableTransfer
        )
    }

    @Test(
        "foreign worktree continuity is uncertain for every non-proving ancestry disposition",
        arguments: [
            WorktreeAnnotationAncestryDisposition.notEvaluated,
            .atLeastLimit,
            .traversalLimitReached,
            .unrelated,
            .readFailure,
        ]
    )
    func nonProvingAncestryIsUncertain(
        ancestry: WorktreeAnnotationAncestryDisposition
    ) throws {
        let accepted = try context(repositoryID: "repo", worktreeID: "worktree-a")
        let current = try context(repositoryID: "repo", worktreeID: "worktree-b")

        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: current,
                ancestry: ancestry
            ) == .uncertain
        )
    }

    @Test("foreign worktree branch mismatch or missing evidence is uncertain")
    func foreignWorktreeEvidenceMismatchIsUncertain() throws {
        let accepted = try context(repositoryID: "repo", worktreeID: "worktree-a")

        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: try context(
                    repositoryID: "repo",
                    worktreeID: "worktree-b",
                    branchName: "feature/other"
                ),
                ancestry: .exact
            ) == .uncertain
        )
        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: .init(repositoryID: "repo", worktreeID: "worktree-b", reviewedSubject: nil),
                ancestry: .exact
            ) == .uncertain
        )
        #expect(
            WorktreeAnnotationContinuityClassifier.classify(
                accepted: accepted,
                current: .init(repositoryID: nil, worktreeID: nil, reviewedSubject: nil),
                ancestry: .readFailure
            ) == .uncertain
        )
    }
}

private func context(
    repositoryID: String,
    worktreeID: String,
    branchName: String = "feature/review",
    reviewedHeadOID: String = "1111111111111111111111111111111111111111"
) throws -> WorktreeAnnotationReviewedSubjectContext {
    try .init(
        repositoryID: repositoryID,
        worktreeID: worktreeID,
        reviewedSubject: .init(branchName: branchName, reviewedHeadOID: reviewedHeadOID)
    )
}
