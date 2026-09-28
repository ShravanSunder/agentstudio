import AgentStudioGit
import Foundation

/// A repository's locally known default starting point; resolution never fetches.
package enum WorktreeDefaultStartPoint: Equatable, Sendable {
    case resolved(displayRef: String, startPoint: String)
    case noDefaultBranch
}

package protocol WorktreeDefaultStartPointResolving: Sendable {
    func resolveDefaultStartPoint(repositoryPath: URL) async throws(GitDataPlaneError) -> WorktreeDefaultStartPoint
}
