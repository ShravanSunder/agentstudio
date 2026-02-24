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
                        displayName: displayName,
                        repoName: repos.first?.name ?? "repo",
                        worktreeCommonDirectory: nil,
                        folderCwd: "/tmp",
                        parentFolder: "tmp",
                        organizationName: "acme",
                        originRemote: "git@github.com:acme/monorepo.git",
                        upstreamRemote: nil,
                        lastPathComponent: repos.first?.name ?? "repo",
                        worktreeCwds: [],
                        remoteFingerprint: "github.com/acme/monorepo",
                        remoteSlug: "acme/monorepo"
                    )
                )
            }
        )
    }

    static func normalizedWorktreePaths(in group: SidebarRepoGroup) -> [String] {
        group.repos
            .flatMap(\.worktrees)
            .map { $0.path.standardizedFileURL.path }
    }
}
