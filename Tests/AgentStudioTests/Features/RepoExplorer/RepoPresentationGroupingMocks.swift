import Foundation

@testable import AgentStudio

enum SidebarRepoGroupingMocks {
    static func metadata(
        for repos: [Repo],
        groupKey: String = "remote:github.com/acme/monorepo",
        displayName: String = "acme/monorepo"
    ) -> [UUID: RepoIdentityMetadata] {
        Dictionary(
            uniqueKeysWithValues: repos.map { repo in
                (
                    repo.id,
                    RepoIdentityMetadata(
                        groupKey: groupKey,
                        repoName: repos.first?.name ?? "repo",
                        organizationName: "acme",
                        lastPathComponent: repos.first?.name ?? "repo"
                    )
                )
            }
        )
    }

    static func normalizedWorktreePaths(in group: RepoPresentationGroup) -> [String] {
        group.repos
            .flatMap(\.worktrees)
            .map { $0.path.standardizedFileURL.path }
    }
}
