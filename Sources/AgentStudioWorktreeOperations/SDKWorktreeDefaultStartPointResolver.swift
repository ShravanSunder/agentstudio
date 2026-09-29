import AgentStudioGit
import Foundation

/// Uses the SDK's origin/HEAD resolution, then local main/master branch facts.
package struct SDKWorktreeDefaultStartPointResolver: WorktreeDefaultStartPointResolving {
    private let client: any AgentStudioGitLocalClient

    package init(client: any AgentStudioGitLocalClient = LibGit2AgentStudioGitLocalClient()) {
        self.client = client
    }

    @concurrent
    package func resolveDefaultStartPoint(repositoryPath: URL) async throws(GitDataPlaneError)
        -> WorktreeDefaultStartPoint
    {
        if let originHead = try await client.resolveReviewDefaultTarget(for: repositoryPath),
            case .remoteTracking(let remoteName, _, _) = originHead,
            remoteName == "origin"
        {
            return .resolved(displayRef: originHead.displayName, startPoint: originHead.referenceName)
        }
        let branches = try await client.branches(for: repositoryPath)
        for branchName in ["main", "master"] where branches.contains(where: { $0.name == branchName }) {
            return .resolved(displayRef: branchName, startPoint: "refs/heads/\(branchName)")
        }
        return .noDefaultBranch
    }
}
