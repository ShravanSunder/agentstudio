import AgentStudioInfrastructure
import Foundation
import Observation

private struct RepositoryTopologyPathIndexEntry: Sendable {
    let repoId: UUID
    let worktreeId: UUID
    let normalizedWorktreePath: String
    let repoWorktreeCount: Int
    let repoPathMatchesWorktree: Bool
    let isMainWorktree: Bool
    let stableTieBreaker: String
}

package struct RepositoryTopologyReadSnapshot: Sendable {
    fileprivate let repositoriesByID: [UUID: Repo]
    fileprivate let worktreesByID: [UUID: Worktree]
    fileprivate let worktreePathIndex: [RepositoryTopologyPathIndexEntry]
    fileprivate let unavailableRepositoryIDs: Set<UUID>

    fileprivate nonisolated init(
        repositoriesByID: [UUID: Repo],
        worktreesByID: [UUID: Worktree],
        worktreePathIndex: [RepositoryTopologyPathIndexEntry],
        unavailableRepositoryIDs: Set<UUID>
    ) {
        self.repositoriesByID = repositoriesByID
        self.worktreesByID = worktreesByID
        self.worktreePathIndex = worktreePathIndex
        self.unavailableRepositoryIDs = unavailableRepositoryIDs
    }

    nonisolated init(replacement: RepositoryTopologyReplacement) {
        self.init(
            repositoriesByID: Dictionary(
                uniqueKeysWithValues: replacement.repositories.map { ($0.id, $0) }
            ),
            worktreesByID: Dictionary(
                uniqueKeysWithValues: replacement.repositories.flatMap(\.worktrees).map { ($0.id, $0) }
            ),
            worktreePathIndex: makeRepositoryTopologyPathIndex(
                repositories: replacement.repositories,
                unavailableRepositoryIDs: replacement.unavailableRepositoryIDs
            ),
            unavailableRepositoryIDs: replacement.unavailableRepositoryIDs
        )
    }

    package func repo(_ id: UUID) -> Repo? {
        repositoriesByID[id]
    }

    package func worktree(_ id: UUID) -> Worktree? {
        worktreesByID[id]
    }

    package func validatedAssociation(
        repoId: UUID?,
        worktreeId: UUID?
    ) -> (repo: Repo, worktree: Worktree)? {
        guard
            let repoId,
            let worktreeId,
            !unavailableRepositoryIDs.contains(repoId),
            let repository = repo(repoId),
            let worktree = worktree(worktreeId),
            worktree.repoId == repository.id
        else { return nil }
        return (repository, worktree)
    }

    package func isKnownAssociationTemporarilyUnavailable(
        repoId: UUID?,
        worktreeId: UUID?
    ) -> Bool {
        guard
            let repoId,
            let worktreeId,
            unavailableRepositoryIDs.contains(repoId),
            repo(repoId) != nil
        else { return false }
        guard let knownWorktree = worktree(worktreeId) else { return true }
        return knownWorktree.repoId == repoId
    }

    package func repoAndWorktree(
        containing cwd: URL?,
        cancellationCheck: () throws(CancellationError) -> Void
    ) throws(CancellationError) -> (repo: Repo, worktree: Worktree)? {
        guard let cwd else { return nil }
        let normalizedCWD = cwd.standardizedFileURL.path

        for entry in worktreePathIndex {
            try cancellationCheck()
            guard
                normalizedCWD == entry.normalizedWorktreePath
                    || normalizedCWD.hasPrefix(entry.normalizedWorktreePath + "/")
            else { continue }
            guard
                let repository = repositoriesByID[entry.repoId],
                let worktree = worktreesByID[entry.worktreeId]
            else { return nil }
            return (repository, worktree)
        }
        return nil
    }

    package func repoAndWorktree(
        containing cwd: URL?
    ) -> (repo: Repo, worktree: Worktree)? {
        do {
            return try repoAndWorktree(containing: cwd, cancellationCheck: {})
        } catch {
            return nil
        }
    }

    package func hasUnavailableWorktree(containing cwd: URL?) -> Bool {
        guard let cwd else { return false }
        let normalizedCWD = cwd.standardizedFileURL.path
        return unavailableRepositoryIDs.contains { repositoryID in
            guard let repository = repositoriesByID[repositoryID] else { return false }
            return repository.worktrees.contains { worktree in
                let normalizedWorktreePath = worktree.path.standardizedFileURL.path
                return normalizedCWD == normalizedWorktreePath
                    || normalizedCWD.hasPrefix(normalizedWorktreePath + "/")
            }
        }
    }
}

@MainActor
@Observable
package final class RepositoryTopologyAtom {
    package private(set) var repos: [Repo] = []
    package private(set) var watchedPaths: [WatchedPath] = []
    private(set) var unavailableRepoIds: Set<UUID> = []
    package private(set) var worktreePathIndexGeneration: UInt64 = 0

    @ObservationIgnored private let repositoryFamily = AtomFamily<UUID, Repo>(
        telemetryLabel: "repository_topology_repository",
        isContentEqual: ==
    )
    @ObservationIgnored private let worktreeFamily = AtomFamily<UUID, Worktree>(
        telemetryLabel: "repository_topology_worktree",
        isContentEqual: ==
    )
    @ObservationIgnored private let topologyRevisionAtom = AtomRevision()
    @ObservationIgnored private let orderedMembershipRevisionAtom = AtomRevision()
    @ObservationIgnored private var worktreePathIndex: [RepositoryTopologyPathIndexEntry] = []
    @ObservationIgnored private var deferredWorktreePathIndexRebuildDepth = 0
    @ObservationIgnored private var deferredWorktreePathIndexRebuildNeeded = false
    @ObservationIgnored private var repositoriesByID: [UUID: Repo] = [:]
    @ObservationIgnored private var worktreesByID: [UUID: Worktree] = [:]
    @ObservationIgnored private var watchedPathsByID: [UUID: WatchedPath] = [:]
    @ObservationIgnored private var repositoryIDsByStableKey: [String: UUID] = [:]
    @ObservationIgnored private var worktreeIDsByStableKey: [String: UUID] = [:]
    @ObservationIgnored private var orderedRepositoryIDs: [UUID] = []
    @ObservationIgnored private var orderedWorktreeIDs: [UUID] = []
    @ObservationIgnored private var worktreePathAmbiguityReporter: (@MainActor () -> Void)?

    package init() {}

    package func setWorktreePathAmbiguityReporter(
        _ reporter: (@MainActor () -> Void)?
    ) {
        worktreePathAmbiguityReporter = reporter
    }

    var allWorktreeIds: Set<UUID> {
        _ = orderedMembershipRevisionAtom.value
        return worktreeFamily.membershipKeys()
    }

    package var repositoryIdsInOrder: [UUID] {
        _ = orderedMembershipRevisionAtom.value
        return orderedRepositoryIDs
    }

    package var worktreeIdsInOrder: [UUID] {
        _ = orderedMembershipRevisionAtom.value
        return orderedWorktreeIDs
    }

    var watchedPathIdsInOrder: [UUID] {
        watchedPaths.map(\.id)
    }

    package var worktreePathIndexCount: Int {
        worktreePathIndex.count
    }

    func withDeferredWorktreePathIndexRebuild(_ mutation: () -> Void) {
        deferredWorktreePathIndexRebuildDepth += 1
        defer {
            deferredWorktreePathIndexRebuildDepth -= 1
            if deferredWorktreePathIndexRebuildDepth == 0, deferredWorktreePathIndexRebuildNeeded {
                deferredWorktreePathIndexRebuildNeeded = false
                rebuildWorktreePathIndexAndBumpGeneration()
            }
        }
        mutation()
    }

    func replaceTopology(_ replacement: RepositoryTopologyReplacement) {
        let repositoriesChanged = repos != replacement.repositories
        let watchedPathsChanged = watchedPaths != replacement.watchedPaths
        let unavailableRepositoriesChanged = unavailableRepoIds != replacement.unavailableRepositoryIDs
        guard repositoriesChanged || watchedPathsChanged || unavailableRepositoriesChanged else { return }

        if repositoriesChanged {
            let previousRepositoryIDs = orderedRepositoryIDs
            let previousWorktreeIDs = orderedWorktreeIDs
            repos = replacement.repositories
            orderedRepositoryIDs = replacement.repositories.map(\.id)
            orderedWorktreeIDs = replacement.repositories.flatMap(\.worktrees).map(\.id)
            synchronizeEntityFamilies()
            if previousRepositoryIDs != orderedRepositoryIDs
                || previousWorktreeIDs != orderedWorktreeIDs
            {
                orderedMembershipRevisionAtom.bump()
            }
        }
        if watchedPathsChanged {
            watchedPaths = replacement.watchedPaths
        }
        if unavailableRepositoriesChanged {
            unavailableRepoIds = replacement.unavailableRepositoryIDs
        }
        if repositoriesChanged || watchedPathsChanged {
            rebuildEntityIndexes()
        }
        if repositoriesChanged || unavailableRepositoriesChanged {
            scheduleWorktreePathIndexRebuild()
        }
    }

    package func repo(_ id: UUID) -> Repo? {
        repositoryFamily.value(for: id)
    }

    package func worktree(_ id: UUID) -> Worktree? {
        worktreeFamily.value(for: id)
    }

    package func validatedAssociation(
        repoId: UUID?,
        worktreeId: UUID?
    ) -> (repo: Repo, worktree: Worktree)? {
        guard
            let repoId,
            let worktreeId,
            !isRepoUnavailable(repoId),
            let repository = repo(repoId),
            let worktree = worktree(worktreeId),
            worktree.repoId == repository.id
        else { return nil }
        return (repository, worktree)
    }

    package func repo(stableKey: String) -> Repo? {
        _ = orderedMembershipRevisionAtom.value
        guard let repositoryID = repositoryIDsByStableKey[stableKey] else { return nil }
        return repo(repositoryID)
    }

    package func worktree(stableKey: String) -> Worktree? {
        _ = orderedMembershipRevisionAtom.value
        guard let worktreeID = worktreeIDsByStableKey[stableKey] else { return nil }
        return worktree(worktreeID)
    }

    package func activationWorktree(for recentEntity: ApplicationRecentEntity) -> Worktree? {
        switch recentEntity {
        case .repository(let repositoryStableKey):
            guard
                let repository = repo(stableKey: repositoryStableKey),
                !isRepoUnavailable(repository.id)
            else {
                return nil
            }
            return repository.worktrees.first(where: \.isMainWorktree)
                ?? repository.worktrees.first
        case .worktree(let worktreeStableKey):
            guard
                let worktree = worktree(stableKey: worktreeStableKey),
                let repository = repo(containing: worktree.id),
                !isRepoUnavailable(repository.id)
            else {
                return nil
            }
            return worktree
        }
    }

    func watchedPath(_ id: UUID) -> WatchedPath? {
        _ = watchedPaths
        return watchedPathsByID[id]
    }

    package func repo(containing worktreeId: UUID) -> Repo? {
        guard let worktree = worktree(worktreeId) else { return nil }
        return repo(worktree.repoId)
    }

    package func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        captureReadSnapshot().repoAndWorktree(containing: cwd)
    }

    package func repoAndWorktree(
        containing cwd: URL?,
        among worktreeIDs: Set<UUID>
    ) -> (repo: Repo, worktree: Worktree)? {
        _ = worktreePathIndexGeneration
        guard let cwd else { return nil }
        let normalizedCWD = cwd.standardizedFileURL.path

        for entry in worktreePathIndex where worktreeIDs.contains(entry.worktreeId) {
            guard
                normalizedCWD == entry.normalizedWorktreePath
                    || normalizedCWD.hasPrefix(entry.normalizedWorktreePath + "/")
            else { continue }
            guard
                let repository = repo(entry.repoId),
                let worktree = worktree(entry.worktreeId)
            else { return nil }
            return (repository, worktree)
        }
        for worktreeID in worktreeIDs {
            _ = worktree(worktreeID)
        }
        return nil
    }

    package func captureReadSnapshot() -> RepositoryTopologyReadSnapshot {
        _ = repos
        _ = worktreePathIndexGeneration
        return RepositoryTopologyReadSnapshot(
            repositoriesByID: repositoriesByID,
            worktreesByID: worktreesByID,
            worktreePathIndex: worktreePathIndex,
            unavailableRepositoryIDs: unavailableRepoIds
        )
    }

    func applyValidatedRepositoryMetadata(
        repositoryID: UUID,
        isFavorite: Bool,
        note: String?,
        tags: [String]
    ) {
        guard let repositoryIndex = repos.firstIndex(where: { $0.id == repositoryID }) else { return }
        var repository = repos[repositoryIndex]
        guard
            repository.isFavorite != isFavorite
                || repository.note != note
                || repository.tags != tags
        else { return }

        repository.isFavorite = isFavorite
        repository.note = note
        repository.tags = tags
        repos[repositoryIndex] = repository
        repositoriesByID[repositoryID] = repository
        let mutation = AtomMutationContext(aggregateRevision: topologyRevisionAtom)
        repositoryFamily.setValue(repository, for: repositoryID, mutation: mutation)
        mutation.commit()
    }

    func applyValidatedWorktreeNote(worktreeID: UUID, note: String?) {
        guard
            let worktree = worktreesByID[worktreeID],
            let repositoryIndex = repos.firstIndex(where: { $0.id == worktree.repoId }),
            let worktreeIndex = repos[repositoryIndex].worktrees.firstIndex(where: { $0.id == worktreeID }),
            repos[repositoryIndex].worktrees[worktreeIndex].note != note
        else { return }

        repos[repositoryIndex].worktrees[worktreeIndex].note = note
        let updatedWorktree = repos[repositoryIndex].worktrees[worktreeIndex]
        worktreesByID[worktreeID] = updatedWorktree
        repositoriesByID[worktree.repoId] = repos[repositoryIndex]
        let mutation = AtomMutationContext(aggregateRevision: topologyRevisionAtom)
        worktreeFamily.setValue(updatedWorktree, for: worktreeID, mutation: mutation)
        repositoryFamily.setValue(repos[repositoryIndex], for: worktree.repoId, mutation: mutation)
        mutation.commit()
    }

    package func isRepoUnavailable(_ repoId: UUID) -> Bool {
        unavailableRepoIds.contains(repoId)
    }

    private func scheduleWorktreePathIndexRebuild() {
        guard deferredWorktreePathIndexRebuildDepth == 0 else {
            deferredWorktreePathIndexRebuildNeeded = true
            return
        }
        rebuildWorktreePathIndexAndBumpGeneration()
    }

    private func rebuildEntityIndexes() {
        repositoriesByID = Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0) })
        worktreesByID = Dictionary(uniqueKeysWithValues: repos.flatMap(\.worktrees).map { ($0.id, $0) })
        watchedPathsByID = Dictionary(uniqueKeysWithValues: watchedPaths.map { ($0.id, $0) })
        repositoryIDsByStableKey = Dictionary(uniqueKeysWithValues: repos.map { ($0.stableKey, $0.id) })
        worktreeIDsByStableKey = Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: repos.flatMap(\.worktrees), by: \.stableKey)
                .compactMap { stableKey, worktrees in
                    worktrees.count == 1 ? (stableKey, worktrees[0].id) : nil
                }
        )
    }

    private func synchronizeEntityFamilies() {
        let mutation = AtomMutationContext(aggregateRevision: topologyRevisionAtom)
        repositoryFamily.replaceAll(
            Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0) }),
            mutation: mutation
        )
        worktreeFamily.replaceAll(
            Dictionary(uniqueKeysWithValues: repos.flatMap(\.worktrees).map { ($0.id, $0) }),
            mutation: mutation
        )
        mutation.commit()
    }

    private func rebuildWorktreePathIndexAndBumpGeneration() {
        worktreePathIndex = makeRepositoryTopologyPathIndex(
            repositories: repos,
            unavailableRepositoryIDs: unavailableRepoIds
        )

        worktreePathIndexGeneration &+= 1
        let stableKeyCounts = Dictionary(grouping: repos.flatMap(\.worktrees), by: \.stableKey)
        if stableKeyCounts.values.contains(where: { $0.count > 1 }) {
            worktreePathAmbiguityReporter?()
        }
    }

}

private nonisolated func makeRepositoryTopologyPathIndex(
    repositories: [Repo],
    unavailableRepositoryIDs: Set<UUID>
) -> [RepositoryTopologyPathIndexEntry] {
    repositories.flatMap { repository -> [RepositoryTopologyPathIndexEntry] in
        guard !unavailableRepositoryIDs.contains(repository.id) else { return [] }
        let normalizedRepositoryPath = repository.repoPath.standardizedFileURL.path
        let normalizedWorktrees = repository.worktrees.map { worktree in
            (worktree: worktree, normalizedPath: worktree.path.standardizedFileURL.path)
        }
        let repositoryPathMatchesAnyWorktree = normalizedWorktrees.contains {
            $0.normalizedPath == normalizedRepositoryPath
        }

        return normalizedWorktrees.map { item in
            RepositoryTopologyPathIndexEntry(
                repoId: repository.id,
                worktreeId: item.worktree.id,
                normalizedWorktreePath: item.normalizedPath,
                repoWorktreeCount: repository.worktrees.count,
                repoPathMatchesWorktree: repositoryPathMatchesAnyWorktree
                    && normalizedRepositoryPath == item.normalizedPath,
                isMainWorktree: item.worktree.isMainWorktree,
                stableTieBreaker: "\(repository.id.uuidString)|\(item.worktree.id.uuidString)"
            )
        }
    }
    .sorted(by: repositoryTopologyPathIndexEntryPrecedes)
}

private nonisolated func repositoryTopologyPathIndexEntryPrecedes(
    lhs: RepositoryTopologyPathIndexEntry,
    rhs: RepositoryTopologyPathIndexEntry
) -> Bool {
    if lhs.normalizedWorktreePath.count != rhs.normalizedWorktreePath.count {
        return lhs.normalizedWorktreePath.count > rhs.normalizedWorktreePath.count
    }
    if lhs.repoWorktreeCount != rhs.repoWorktreeCount {
        return lhs.repoWorktreeCount < rhs.repoWorktreeCount
    }
    if lhs.repoPathMatchesWorktree != rhs.repoPathMatchesWorktree {
        return lhs.repoPathMatchesWorktree && !rhs.repoPathMatchesWorktree
    }
    if lhs.isMainWorktree != rhs.isMainWorktree {
        return !lhs.isMainWorktree && rhs.isMainWorktree
    }
    return lhs.stableTieBreaker < rhs.stableTieBreaker
}
