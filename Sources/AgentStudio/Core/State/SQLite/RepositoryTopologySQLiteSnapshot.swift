import Foundation

struct RepositoryTopologySQLiteSnapshot: Equatable, Sendable {
    let repos: [CanonicalRepo]
    let worktrees: [CanonicalWorktree]
    let unavailableRepoIds: Set<UUID>
    let watchedPaths: [WatchedPath]
    let watchedPathStableKeysByID: [UUID: String]
    let updatedAt: Date

    init(
        repos: [CanonicalRepo] = [],
        worktrees: [CanonicalWorktree] = [],
        unavailableRepoIds: Set<UUID> = [],
        watchedPaths: [WatchedPath] = [],
        watchedPathStableKeysByID: [UUID: String]? = nil,
        updatedAt: Date
    ) {
        self.repos = repos
        self.worktrees = worktrees
        self.unavailableRepoIds = unavailableRepoIds
        self.watchedPaths = watchedPaths
        self.watchedPathStableKeysByID =
            watchedPathStableKeysByID
            ?? Dictionary(uniqueKeysWithValues: watchedPaths.map { ($0.id, $0.stableKey) })
        self.updatedAt = updatedAt
    }
}

struct WorkspaceSQLiteSaveBundle: Equatable, Sendable {
    let workspace: WorkspaceSQLiteSnapshot
    let captureRevision: WorkspaceCompositionRevision?

    var id: UUID { workspace.id }
    var updatedAt: Date { workspace.updatedAt }

    init(workspace: WorkspaceSQLiteSnapshot, captureRevision: WorkspaceCompositionRevision? = nil) {
        self.workspace = workspace
        self.captureRevision = captureRevision
    }
}

struct WorkspaceCoreLoadSnapshot: Equatable, Sendable {
    let workspace: WorkspaceSQLiteSnapshot
    let repositoryTopology: RepositoryTopologySQLiteSnapshot
    let persistenceReasons: Set<PaneTopologyPersistenceReason>
}
