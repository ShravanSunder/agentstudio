import Foundation

struct RepositoryTopologySQLiteSnapshot: Equatable, Sendable {
    let repos: [CanonicalRepo]
    let worktrees: [CanonicalWorktree]
    let absenceRecords: RepositoryTopologyAbsenceRecords
    var unavailableRepoIds: Set<UUID> { absenceRecords.unavailableRepositoryIDs }
    let watchedPaths: [WatchedPath]
    let watchedPathStableKeysByID: [UUID: String]
    let updatedAt: Date

    init(
        repos: [CanonicalRepo] = [],
        worktrees: [CanonicalWorktree] = [],
        unavailableRepoIds: Set<UUID> = [],
        watchedPaths: [WatchedPath] = [],
        watchedPathStableKeysByID: [UUID: String]? = nil,
        updatedAt: Date,
        absenceRecords: RepositoryTopologyAbsenceRecords = .init()
    ) {
        self.repos = repos
        self.worktrees = worktrees
        self.absenceRecords = absenceRecords.addingLegacyUnavailableRepositories(unavailableRepoIds)
        self.watchedPaths = watchedPaths
        self.watchedPathStableKeysByID =
            watchedPathStableKeysByID
            ?? Dictionary(uniqueKeysWithValues: watchedPaths.map { ($0.id, $0.stableKey) })
        self.updatedAt = updatedAt
    }
}

/// Captured receiver navigation for one ordinary save. `nil` on a bundle means
/// the saving owner does not own navigation and its rows stay untouched.
struct BridgeNavigationSaveSnapshot: Equatable, Sendable {
    let records: [BridgeReceiver: BridgeNavigationRecord]
    let revision: Int
}

struct WorkspaceSQLiteSaveBundle: Equatable, Sendable {
    let workspace: WorkspaceSQLiteSnapshot
    let captureRevision: WorkspaceCompositionRevision?
    let bridgeNavigation: BridgeNavigationSaveSnapshot?

    var id: UUID { workspace.id }
    var updatedAt: Date { workspace.updatedAt }

    init(
        workspace: WorkspaceSQLiteSnapshot,
        captureRevision: WorkspaceCompositionRevision? = nil,
        bridgeNavigation: BridgeNavigationSaveSnapshot? = nil
    ) {
        self.workspace = workspace
        self.captureRevision = captureRevision
        self.bridgeNavigation = bridgeNavigation
    }
}

struct WorkspaceCoreLoadSnapshot: Equatable, Sendable {
    let workspace: WorkspaceSQLiteSnapshot
    let repositoryTopology: RepositoryTopologySQLiteSnapshot
    let persistenceReasons: Set<PaneTopologyPersistenceReason>
}
