import Foundation

package enum RepositoryTopologyIdentityRejection: Error, Equatable, Sendable {
    case missingRepositoryStableKey(UUID)
    case unexpectedRepositoryStableKey(UUID)
    case missingWorktreeStableKey(UUID)
    case unexpectedWorktreeStableKey(UUID)
    case missingWatchedPathStableKey(UUID)
    case unexpectedWatchedPathStableKey(UUID)
    case duplicateRepositoryID(UUID)
    case duplicateRepositoryStableKey(String)
    case duplicateWorktreeID(UUID)
    case duplicateWorktreeStableKey(String)
    case duplicateWatchedPathID(UUID)
    case duplicateWatchedPathStableKey(String)
    case worktreeRepositoryMissing(worktreeID: UUID, repositoryID: UUID)
    case unavailableRepositoryMissing(UUID)
    case availableRepositoryMainWorktreeMissing(UUID)
    case availableRepositoryHasMultipleMainWorktrees(UUID)
    case availableRepositoryMainWorktreePathMismatch(UUID)
}

package struct RepositoryTopologyStableIdentity: Equatable, Sendable {
    package let repositoryStableKeysByID: [UUID: String]
    package let worktreeStableKeysByID: [UUID: String]
    package let watchedPathStableKeysByID: [UUID: String]

    package init(
        repositoryStableKeysByID: [UUID: String],
        worktreeStableKeysByID: [UUID: String],
        watchedPathStableKeysByID: [UUID: String]
    ) {
        self.repositoryStableKeysByID = repositoryStableKeysByID
        self.worktreeStableKeysByID = worktreeStableKeysByID
        self.watchedPathStableKeysByID = watchedPathStableKeysByID
    }

    package nonisolated static func derived(
        repositories: [Repo],
        watchedPaths: [WatchedPath]
    ) -> Self {
        Self(
            repositoryStableKeysByID: Dictionary(
                uniqueKeysWithValues: repositories.map { ($0.id, $0.stableKey) }
            ),
            worktreeStableKeysByID: Dictionary(
                uniqueKeysWithValues: repositories.flatMap(\.worktrees).map { ($0.id, $0.stableKey) }
            ),
            watchedPathStableKeysByID: Dictionary(
                uniqueKeysWithValues: watchedPaths.map { ($0.id, $0.stableKey) }
            )
        )
    }
}

enum RepositoryTopologyReplacementPreparation: Sendable {
    case prepared(RepositoryTopologyReplacement)
    case rejected(RepositoryTopologyIdentityRejection)
}

struct RepositoryTopologyReplacement: Sendable {
    let repositories: [Repo]
    let watchedPaths: [WatchedPath]
    let unavailableRepositoryIDs: Set<UUID>
    let repositoryStableKeysByID: [UUID: String]
    let worktreeStableKeysByID: [UUID: String]
    let watchedPathStableKeysByID: [UUID: String]

    private init(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>,
        stableIdentity: RepositoryTopologyStableIdentity
    ) {
        self.repositories = repositories
        self.watchedPaths = watchedPaths
        self.unavailableRepositoryIDs = unavailableRepositoryIDs
        self.repositoryStableKeysByID = stableIdentity.repositoryStableKeysByID
        self.worktreeStableKeysByID = stableIdentity.worktreeStableKeysByID
        self.watchedPathStableKeysByID = stableIdentity.watchedPathStableKeysByID
    }

    nonisolated static func prepare(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>,
        stableIdentity: RepositoryTopologyStableIdentity
    ) -> RepositoryTopologyReplacementPreparation {
        if let rejection = validateIdentity(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs,
            stableIdentity: stableIdentity
        ) {
            return .rejected(rejection)
        }
        return .prepared(
            .init(
                repositories: repositories,
                watchedPaths: watchedPaths,
                unavailableRepositoryIDs: unavailableRepositoryIDs,
                stableIdentity: stableIdentity
            )
        )
    }

    nonisolated static func prepare(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) -> RepositoryTopologyReplacementPreparation {
        prepare(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs,
            stableIdentity: .derived(repositories: repositories, watchedPaths: watchedPaths)
        )
    }

    private nonisolated static func validateIdentity(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>,
        stableIdentity: RepositoryTopologyStableIdentity
    ) -> RepositoryTopologyIdentityRejection? {
        var repositoryIDs = Set<UUID>()
        var worktreeIDs = Set<UUID>()
        var watchedPathIDs = Set<UUID>()
        for repository in repositories {
            guard repositoryIDs.insert(repository.id).inserted else {
                return .duplicateRepositoryID(repository.id)
            }
            for worktree in repository.worktrees {
                guard worktreeIDs.insert(worktree.id).inserted else {
                    return .duplicateWorktreeID(worktree.id)
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
        }
        if let missingID = repositoryIDs.first(where: { stableIdentity.repositoryStableKeysByID[$0] == nil }) {
            return .missingRepositoryStableKey(missingID)
        }
        if let unexpectedID = stableIdentity.repositoryStableKeysByID.keys.first(where: { !repositoryIDs.contains($0) })
        {
            return .unexpectedRepositoryStableKey(unexpectedID)
        }
        if let missingID = worktreeIDs.first(where: { stableIdentity.worktreeStableKeysByID[$0] == nil }) {
            return .missingWorktreeStableKey(missingID)
        }
        if let unexpectedID = stableIdentity.worktreeStableKeysByID.keys.first(where: { !worktreeIDs.contains($0) }) {
            return .unexpectedWorktreeStableKey(unexpectedID)
        }
        if let missingID = watchedPathIDs.first(where: { stableIdentity.watchedPathStableKeysByID[$0] == nil }) {
            return .missingWatchedPathStableKey(missingID)
        }
        if let unexpectedID = stableIdentity.watchedPathStableKeysByID.keys.first(where: {
            !watchedPathIDs.contains($0)
        }) {
            return .unexpectedWatchedPathStableKey(unexpectedID)
        }
        if let duplicate = duplicateStableKey(in: stableIdentity.repositoryStableKeysByID.values) {
            return .duplicateRepositoryStableKey(duplicate)
        }
        if let duplicate = duplicateStableKey(in: stableIdentity.worktreeStableKeysByID.values) {
            return .duplicateWorktreeStableKey(duplicate)
        }
        if let duplicate = duplicateStableKey(in: stableIdentity.watchedPathStableKeysByID.values) {
            return .duplicateWatchedPathStableKey(duplicate)
        }
        if let missingID = unavailableRepositoryIDs.first(where: { !repositoryIDs.contains($0) }) {
            return .unavailableRepositoryMissing(missingID)
        }
        for repository in repositories where !unavailableRepositoryIDs.contains(repository.id) {
            let mainWorktrees = repository.worktrees.filter(\.isMainWorktree)
            guard !mainWorktrees.isEmpty else {
                return .availableRepositoryMainWorktreeMissing(repository.id)
            }
            guard mainWorktrees.count == 1 else {
                return .availableRepositoryHasMultipleMainWorktrees(repository.id)
            }
            guard let mainWorktree = mainWorktrees.first,
                mainWorktree.path.standardizedFileURL == repository.repoPath.standardizedFileURL,
                stableIdentity.worktreeStableKeysByID[mainWorktree.id]
                    == stableIdentity.repositoryStableKeysByID[repository.id]
            else {
                return .availableRepositoryMainWorktreePathMismatch(repository.id)
            }
        }
        return nil
    }

    private nonisolated static func duplicateStableKey(
        in stableKeys: Dictionary<UUID, String>.Values
    ) -> String? {
        var seen = Set<String>()
        return stableKeys.first(where: { !seen.insert($0).inserted })
    }
}
