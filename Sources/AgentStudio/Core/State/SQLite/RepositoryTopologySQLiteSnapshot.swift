import Foundation

struct RepositoryTopologySQLiteSnapshot: Equatable, Sendable {
    var id: UUID
    var repos: [CanonicalRepo]
    var worktrees: [CanonicalWorktree]
    var unavailableRepoIds: Set<UUID>
    var watchedPaths: [WatchedPath]
    var updatedAt: Date

    init(
        id: UUID,
        repos: [CanonicalRepo] = [],
        worktrees: [CanonicalWorktree] = [],
        unavailableRepoIds: Set<UUID> = [],
        watchedPaths: [WatchedPath] = [],
        updatedAt: Date
    ) {
        self.id = id
        self.repos = repos
        self.worktrees = worktrees
        self.unavailableRepoIds = unavailableRepoIds
        self.watchedPaths = watchedPaths
        self.updatedAt = updatedAt
    }
}

struct WorkspaceSQLiteSaveBundle: Equatable, Sendable {
    var workspace: WorkspaceSQLiteSnapshot
    var repositoryTopology: RepositoryTopologySQLiteSnapshot

    var id: UUID { workspace.id }
    var updatedAt: Date { workspace.updatedAt }

    init(
        workspace: WorkspaceSQLiteSnapshot,
        repositoryTopology: RepositoryTopologySQLiteSnapshot
    ) {
        precondition(
            workspace.id == repositoryTopology.id,
            "Workspace and repository topology snapshots must share one workspace id"
        )
        precondition(
            workspace.updatedAt == repositoryTopology.updatedAt,
            "Workspace and repository topology snapshots must share one persistedAt generation"
        )
        self.workspace = workspace
        self.repositoryTopology = repositoryTopology
    }
}
