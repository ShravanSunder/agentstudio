import Foundation

/// The annotation subjects one pane surface shows, under the key the page
/// knows that surface's annotations by: the Files collection token, or the
/// Review worktree. The subjects change with Files membership and opened
/// documents; the key stays stable for the surface.
struct WorktreeAnnotationScope: Equatable, Sendable {
    let key: String
    let subjects: Set<WorktreeAnnotationSubject>

    /// The scope of a Review surface: its one Git worktree, keyed by that
    /// worktree.
    static func review(repositoryID: String, worktreeID: String) -> Self {
        Self(key: worktreeID, subjects: [.git(repositoryID: repositoryID, worktreeID: worktreeID)])
    }
}
