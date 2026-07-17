import Foundation

enum RepositoryTopologyIdentityRejection: Error, Equatable, Sendable {
    case duplicateRepositoryID(UUID)
    case duplicateRepositoryStableKey(String)
    case duplicateWorktreeID(UUID)
    case duplicateWorktreeStableKey(String)
    case duplicateWatchedPathID(UUID)
    case duplicateWatchedPathStableKey(String)
    case worktreeRepositoryMissing(worktreeID: UUID, repositoryID: UUID)
    case unavailableRepositoryMissing(UUID)
}

enum RepositoryTopologyReplacementPreparation: Sendable {
    case prepared(RepositoryTopologyReplacement)
    case rejected(RepositoryTopologyIdentityRejection)
}

struct RepositoryTopologyReplacement: Sendable {
    let repositories: [Repo]
    let watchedPaths: [WatchedPath]
    let unavailableRepositoryIDs: Set<UUID>

    private init(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) {
        self.repositories = repositories
        self.watchedPaths = watchedPaths
        self.unavailableRepositoryIDs = unavailableRepositoryIDs
    }

    nonisolated static func prepare(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) -> RepositoryTopologyReplacementPreparation {
        if let rejection = validateIdentity(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs
        ) {
            return .rejected(rejection)
        }
        return .prepared(
            .init(
                repositories: repositories,
                watchedPaths: watchedPaths,
                unavailableRepositoryIDs: unavailableRepositoryIDs
            )
        )
    }

    private nonisolated static func validateIdentity(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) -> RepositoryTopologyIdentityRejection? {
        var repositoryIDs = Set<UUID>()
        var repositoryStableKeys = Set<String>()
        var worktreeIDs = Set<UUID>()
        var worktreeStableKeys = Set<String>()
        var watchedPathIDs = Set<UUID>()
        var watchedPathStableKeys = Set<String>()
        for repository in repositories {
            guard repositoryIDs.insert(repository.id).inserted else {
                return .duplicateRepositoryID(repository.id)
            }
            guard repositoryStableKeys.insert(repository.stableKey).inserted else {
                return .duplicateRepositoryStableKey(repository.stableKey)
            }
            for worktree in repository.worktrees {
                guard worktreeIDs.insert(worktree.id).inserted else {
                    return .duplicateWorktreeID(worktree.id)
                }
                guard worktreeStableKeys.insert(worktree.stableKey).inserted else {
                    return .duplicateWorktreeStableKey(worktree.stableKey)
                }
                guard worktree.repoId == repository.id else {
                    return .worktreeRepositoryMissing(worktreeID: worktree.id, repositoryID: worktree.repoId)
                }
            }
        }
        for watchedPath in watchedPaths {
            guard watchedPathIDs.insert(watchedPath.id).inserted else {
                return .duplicateWatchedPathID(watchedPath.id)
            }
            guard watchedPathStableKeys.insert(watchedPath.stableKey).inserted else {
                return .duplicateWatchedPathStableKey(watchedPath.stableKey)
            }
        }
        if let missingID = unavailableRepositoryIDs.first(where: { !repositoryIDs.contains($0) }) {
            return .unavailableRepositoryMissing(missingID)
        }
        return nil
    }
}
