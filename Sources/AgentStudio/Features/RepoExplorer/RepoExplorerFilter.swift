import Foundation

/// Pure filter logic for sidebar repo/worktree searching.
/// Extracted for testability and single source of truth.
enum RepoExplorerFilter {
    /// Filter repos by a search query with worktree-level granularity.
    ///
    /// - If `query` is empty, returns all repos unchanged.
    /// - If a repo's name matches, all its worktrees are included.
    /// - If only some worktrees match, only those are included under the parent repo.
    /// - Repos with no matches are excluded entirely.
    static func filter(
        repos: [RepoPresentationItem],
        query: String
    ) -> [RepoPresentationItem] {
        guard !query.isEmpty else { return repos }

        return repos.compactMap { repo in
            if repoMatches(repo, query: query) {
                return repo
            }
            let matchingWorktrees = repo.worktrees.filter {
                worktreeMatches($0, query: query)
            }
            guard !matchingWorktrees.isEmpty else { return nil }
            var filtered = repo
            filtered.worktrees = matchingWorktrees
            return filtered
        }
    }

    private static func repoMatches(_ repo: RepoPresentationItem, query: String) -> Bool {
        repo.name.localizedCaseInsensitiveContains(query)
            || repo.tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func worktreeMatches(_ worktree: Worktree, query: String) -> Bool {
        worktree.name.localizedCaseInsensitiveContains(query)
            || worktree.tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
