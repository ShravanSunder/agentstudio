import Foundation

/// Pure filter logic for sidebar repo/worktree searching.
/// Extracted for testability and single source of truth.
enum SidebarFilter {

    /// Filter repos by a search query with worktree-level granularity.
    ///
    /// - If `query` is empty, returns all repos unchanged.
    /// - If a repo's name matches, all its worktrees are included.
    /// - If only some worktrees match, only those are included under the parent repo.
    /// - Repos with no matches are excluded entirely.
    static func filter(repos: [Repo], query: String) -> [Repo] {
        guard !query.isEmpty else { return repos }

        return repos.compactMap { repo in
            if repo.name.localizedCaseInsensitiveContains(query) {
                return repo
            }
            let matchingWorktrees = repo.worktrees.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
            guard !matchingWorktrees.isEmpty else { return nil }
            var filtered = repo
            filtered.worktrees = matchingWorktrees
            return filtered
        }
    }
}
