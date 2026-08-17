import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation comparison label projector")
struct WorktreeAnnotationComparisonLabelProjectorTests {
    @Test("admitted review provenance produces bounded readable comparison context")
    func admittedReviewProvenanceProducesComparisonLabel() throws {
        let targetData = try JSONEncoder().encode(
            WorkspaceReviewContributionTarget.originDefaultBranch(
                remoteName: "origin",
                branchName: "main"
            )
        )
        let target = try #require(String(data: targetData, encoding: .utf8))

        let label = try WorktreeAnnotationComparisonLabelProjector.project(
            .init(
                symbolicTarget: target,
                resolvedTargetOID: "1111111111111111111111111111111111111111",
                reviewedHeadOID: "2222222222222222222222222222222222222222",
                baseRole: "merge_base",
                baseOID: "3333333333333333333333333333333333333333"
            )
        )

        #expect(label == "origin/main → 222222222222")
    }
}
