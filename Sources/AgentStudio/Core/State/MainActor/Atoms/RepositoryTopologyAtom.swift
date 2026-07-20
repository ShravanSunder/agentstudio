import Foundation
import Observation

@MainActor
@Observable
final class RepositoryTopologyAtom {
    private(set) var repos: [Repo] = []
    private(set) var watchedPaths: [WatchedPath] = []
    private(set) var unavailableRepoIds: Set<UUID> = []
    private(set) var worktreePathIndexGeneration: UInt64 = 0

    @ObservationIgnored private var worktreePathIndex: [WorktreePathIndexEntry] = []
    @ObservationIgnored private var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var deferredWorktreePathIndexRebuildDepth = 0
    @ObservationIgnored private var deferredWorktreePathIndexRebuildNeeded = false
    @ObservationIgnored private var repositoriesByID: [UUID: Repo] = [:]
    @ObservationIgnored private var worktreesByID: [UUID: Worktree] = [:]
    @ObservationIgnored private var watchedPathsByID: [UUID: WatchedPath] = [:]

    private struct WorktreePathIndexEntry {
        let repoId: UUID
        let worktreeId: UUID
        let normalizedWorktreePath: String
        let repoWorktreeCount: Int
        let repoPathMatchesWorktree: Bool
        let isMainWorktree: Bool
        let stableTieBreaker: String
    }

    var allWorktreeIds: Set<UUID> {
        _ = repos
        return Set(worktreesByID.keys)
    }

    var repositoryIdsInOrder: [UUID] {
        repos.map(\.id)
    }

    var worktreeIdsInOrder: [UUID] {
        repos.flatMap(\.worktrees).map(\.id)
    }

    var watchedPathIdsInOrder: [UUID] {
        watchedPaths.map(\.id)
    }

    var worktreePathIndexCount: Int {
        worktreePathIndex.count
    }

    func setPerformanceTraceRecorder(_ recorder: AgentStudioPerformanceTraceRecorder?) {
        performanceTraceRecorder = recorder
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
            repos = replacement.repositories
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
        if repositoriesChanged {
            scheduleWorktreePathIndexRebuild()
        }
    }

    func repo(_ id: UUID) -> Repo? {
        _ = repos
        return repositoriesByID[id]
    }

    func worktree(_ id: UUID) -> Worktree? {
        _ = repos
        return worktreesByID[id]
    }

    func watchedPath(_ id: UUID) -> WatchedPath? {
        _ = watchedPaths
        return watchedPathsByID[id]
    }

    func repo(containing worktreeId: UUID) -> Repo? {
        _ = repos
        guard let worktree = worktreesByID[worktreeId] else { return nil }
        return repositoriesByID[worktree.repoId]
    }

    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        guard let cwd else { return nil }
        let clock = ContinuousClock()
        let start = clock.now
        _ = repos
        _ = worktreePathIndexGeneration

        let normalizedCWD = cwd.standardizedFileURL.path
        let match = worktreePathIndex.first(where: {
            normalizedCWD == $0.normalizedWorktreePath
                || normalizedCWD.hasPrefix($0.normalizedWorktreePath + "/")
        })

        performanceTraceRecorder?.recordRepoAndWorktreeLookup(
            duration: start.duration(to: clock.now),
            indexCount: worktreePathIndex.count,
            hasMatch: match != nil,
            fact: AgentStudioPerformanceTraceRecorder.TopologyLookupFact(
                normalizedCWD: normalizedCWD,
                worktreePathIndexGeneration: worktreePathIndexGeneration,
                repoId: match?.repoId,
                worktreeId: match?.worktreeId
            )
        )

        guard
            let match,
            let repository = repositoriesByID[match.repoId],
            let worktree = worktreesByID[match.worktreeId]
        else { return nil }
        return (repository, worktree)
    }

    @discardableResult
    func ensureMainWorktree(at path: URL) -> Worktree {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let repositoryIndex = repos.firstIndex(where: {
            $0.repoPath.standardizedFileURL == normalizedPath || $0.stableKey == incomingStableKey
        }) {
            unavailableRepoIds.remove(repos[repositoryIndex].id)
            if let existingWorktree = repos[repositoryIndex].worktrees.first(where: \.isMainWorktree)
                ?? repos[repositoryIndex].worktrees.first
            {
                return existingWorktree
            }
            let repairedWorktree = Worktree(
                repoId: repos[repositoryIndex].id,
                name: normalizedPath.lastPathComponent,
                path: normalizedPath,
                isMainWorktree: true
            )
            repos[repositoryIndex].name = normalizedPath.lastPathComponent
            repos[repositoryIndex].repoPath = normalizedPath
            repos[repositoryIndex].worktrees = [repairedWorktree]
            rebuildEntityIndexes()
            scheduleWorktreePathIndexRebuild()
            return repairedWorktree
        }

        let repositoryID = UUIDv7.generate()
        let mainWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repositoryID,
            name: normalizedPath.lastPathComponent,
            path: normalizedPath,
            isMainWorktree: true
        )
        repos.append(
            Repo(
                id: repositoryID,
                name: normalizedPath.lastPathComponent,
                repoPath: normalizedPath,
                worktrees: [mainWorktree]
            )
        )
        rebuildEntityIndexes()
        scheduleWorktreePathIndexRebuild()
        return mainWorktree
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
    }

    func isRepoUnavailable(_ repoId: UUID) -> Bool {
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
    }

    private func rebuildWorktreePathIndexAndBumpGeneration() {
        worktreePathIndex = repos.flatMap { repo -> [WorktreePathIndexEntry] in
            let normalizedRepoPath = repo.repoPath.standardizedFileURL.path
            let normalizedWorktrees = repo.worktrees.map { worktree in
                (worktree: worktree, normalizedPath: worktree.path.standardizedFileURL.path)
            }
            let repoPathMatchesAnyWorktree = normalizedWorktrees.contains {
                $0.normalizedPath == normalizedRepoPath
            }

            return normalizedWorktrees.map { item in
                WorktreePathIndexEntry(
                    repoId: repo.id,
                    worktreeId: item.worktree.id,
                    normalizedWorktreePath: item.normalizedPath,
                    repoWorktreeCount: repo.worktrees.count,
                    repoPathMatchesWorktree: repoPathMatchesAnyWorktree
                        && normalizedRepoPath == item.normalizedPath,
                    isMainWorktree: item.worktree.isMainWorktree,
                    stableTieBreaker: "\(repo.id.uuidString)|\(item.worktree.id.uuidString)"
                )
            }
        }
        .sorted(by: Self.worktreePathIndexEntryPrecedes)

        worktreePathIndexGeneration &+= 1
    }

    private static func worktreePathIndexEntryPrecedes(
        lhs: WorktreePathIndexEntry,
        rhs: WorktreePathIndexEntry
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
}
