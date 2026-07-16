import Foundation

enum WorkspaceTopologyPreparationRejection: Error, Equatable, Sendable {
    case worktreeRepositoryMissing(worktreeID: UUID, repositoryID: UUID)
    case invalidIdentity(RepositoryTopologyIdentityRejection)
}

struct PreparedWorkspaceTopology: Sendable {
    let workspaceID: UUID
    let replacement: RepositoryTopologyReplacement
}

enum WorkspaceTopologyPreparationResult: Sendable {
    case prepared(PreparedWorkspaceTopology)
    case rejected(WorkspaceTopologyPreparationRejection)
}

/// Off-MainActor conversion and validation for the independently restored
/// repository/topology domain.
enum WorkspaceTopologyPreparer {
    nonisolated static func prepare(
        _ snapshot: RepositoryTopologySQLiteSnapshot
    ) -> WorkspaceTopologyPreparationResult {
        let repositoryIDs = Set(snapshot.repos.map(\.id))
        if let orphanedWorktree = snapshot.worktrees.first(where: {
            !repositoryIDs.contains($0.repoId)
        }) {
            return .rejected(
                .worktreeRepositoryMissing(
                    worktreeID: orphanedWorktree.id,
                    repositoryID: orphanedWorktree.repoId
                )
            )
        }

        let worktreesByRepositoryID = Dictionary(grouping: snapshot.worktrees, by: \.repoId)
        let repositories = snapshot.repos.map { repository in
            Repo(
                id: repository.id,
                name: repository.name,
                repoPath: repository.repoPath,
                worktrees: (worktreesByRepositoryID[repository.id] ?? []).map { worktree in
                    Worktree(
                        id: worktree.id,
                        repoId: worktree.repoId,
                        name: worktree.name,
                        path: worktree.path,
                        isMainWorktree: worktree.isMainWorktree,
                        tags: worktree.tags
                    )
                },
                createdAt: repository.createdAt,
                tags: repository.tags
            )
        }

        switch RepositoryTopologyReplacement.prepare(
            repositories: repositories,
            watchedPaths: snapshot.watchedPaths,
            unavailableRepositoryIDs: snapshot.unavailableRepoIds
        ) {
        case .prepared(let replacement):
            return .prepared(
                PreparedWorkspaceTopology(
                    workspaceID: snapshot.id,
                    replacement: replacement
                )
            )
        case .rejected(let rejection):
            return .rejected(.invalidIdentity(rejection))
        }
    }
}
