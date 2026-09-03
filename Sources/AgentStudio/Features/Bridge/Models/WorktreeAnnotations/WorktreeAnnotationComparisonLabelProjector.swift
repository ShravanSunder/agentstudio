import AgentStudioCore
import Foundation

enum WorktreeAnnotationComparisonLabelProjector {
    static func project(
        _ origin: WorktreeAnnotationReviewComparisonOrigin?
    ) throws -> String? {
        guard let origin else { return nil }
        guard let data = origin.symbolicTarget.data(using: .utf8) else {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        let target: WorkspaceReviewContributionTarget
        do {
            target = try JSONDecoder().decode(WorkspaceReviewContributionTarget.self, from: data)
        } catch {
            throw WorktreeAnnotationRepositoryError.invalidState
        }
        let targetLabel: String =
            switch target {
            case .localDefaultBranch(let branchName, _): branchName
            case .originDefaultBranch(let remoteName, let branchName, _): "\(remoteName)/\(branchName)"
            case .branch(let name, _), .ref(let name, _): name
            case .commit(let oid): shortenedOID(oid)
            }
        return "\(targetLabel) → \(shortenedOID(origin.reviewedHeadOID))"
    }

    private static func shortenedOID(_ oid: String) -> String {
        String(oid.prefix(12))
    }
}
