import Foundation

struct RepositoryTopologySQLiteSnapshot: Equatable, Sendable {
    let repos: [CanonicalRepo]
    let worktrees: [CanonicalWorktree]
    let unavailableRepoIds: Set<UUID>
    let watchedPaths: [WatchedPath]
    let updatedAt: Date

    init(
        repos: [CanonicalRepo] = [],
        worktrees: [CanonicalWorktree] = [],
        unavailableRepoIds: Set<UUID> = [],
        watchedPaths: [WatchedPath] = [],
        updatedAt: Date
    ) {
        self.repos = repos
        self.worktrees = worktrees
        self.unavailableRepoIds = unavailableRepoIds
        self.watchedPaths = watchedPaths
        self.updatedAt = updatedAt
    }
}

struct WorkspaceSQLiteSaveBundle: Equatable, Sendable {
    let workspace: WorkspaceSQLiteSnapshot

    var id: UUID { workspace.id }
    var updatedAt: Date { workspace.updatedAt }

    init(workspace: WorkspaceSQLiteSnapshot) {
        self.workspace = workspace
    }
}

struct WorkspaceCoreLoadSnapshot: Equatable, Sendable {
    let workspace: WorkspaceSQLiteSnapshot
    let repositoryTopology: RepositoryTopologySQLiteSnapshot
}
