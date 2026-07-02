import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceRepositoryTopologyAtom {
    private(set) var repos: [Repo] = []
    private(set) var watchedPaths: [WatchedPath] = []
    private(set) var unavailableRepoIds: Set<UUID> = []
    private(set) var worktreePathIndexGeneration: UInt64 = 0

    @ObservationIgnored private var worktreePathIndex: [WorktreePathIndexEntry] = []
    @ObservationIgnored private var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var deferredWorktreePathIndexRebuildDepth = 0
    @ObservationIgnored private var deferredWorktreePathIndexRebuildNeeded = false

    private struct WorktreePathIndexEntry {
        let repo: Repo
        let worktree: Worktree
        let normalizedWorktreePath: String
        let repoWorktreeCount: Int
        let repoPathMatchesWorktree: Bool
        let isMainWorktree: Bool
        let stableTieBreaker: String
    }

    var allWorktreeIds: Set<UUID> {
        Set(repos.flatMap(\.worktrees).map(\.id))
    }

    func setPerformanceTraceRecorder(_ recorder: AgentStudioPerformanceTraceRecorder?) {
        performanceTraceRecorder = recorder
    }

    func performBatchedTopologyMutation(_ mutation: () -> Void) {
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

    func hydrate(
        runtimeRepos: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepoIds: Set<UUID>
    ) {
        repos = runtimeRepos
        self.watchedPaths = watchedPaths
        self.unavailableRepoIds = unavailableRepoIds
        scheduleWorktreePathIndexRebuild()
    }

    func repo(_ id: UUID) -> Repo? {
        repos.first { $0.id == id }
    }

    func worktree(_ id: UUID) -> Worktree? {
        repos.flatMap(\.worktrees).first { $0.id == id }
    }

    func repo(containing worktreeId: UUID) -> Repo? {
        repos.first { repo in
            repo.worktrees.contains { $0.id == worktreeId }
        }
    }

    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        guard let cwd else { return nil }
        let clock = ContinuousClock()
        let start = clock.now
        _ = worktreePathIndexGeneration

        let normalizedCWD = cwd.standardizedFileURL.path
        let match = worktreePathIndex.first(where: {
            normalizedCWD == $0.normalizedWorktreePath
                || normalizedCWD.hasPrefix($0.normalizedWorktreePath + "/")
        })

        performanceTraceRecorder?.recordDuration(
            .repoAndWorktreeLookup,
            duration: start.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.topology.index.count": .int(worktreePathIndex.count),
                "agentstudio.performance.topology.has_match": .bool(match != nil),
            ]
        )

        guard let match else { return nil }
        return (match.repo, match.worktree)
    }

    @discardableResult
    func addRepo(at path: URL) -> Repo {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let existing = repos.first(where: {
            $0.repoPath.standardizedFileURL == normalizedPath || $0.stableKey == incomingStableKey
        }) {
            unavailableRepoIds.remove(existing.id)
            return existing
        }

        let repoId = UUID()
        let mainWorktree = Worktree(
            repoId: repoId,
            name: normalizedPath.lastPathComponent,
            path: normalizedPath,
            isMainWorktree: true
        )
        let repo = Repo(
            id: repoId,
            name: normalizedPath.lastPathComponent,
            repoPath: normalizedPath,
            worktrees: [mainWorktree]
        )
        repos.append(repo)
        unavailableRepoIds.remove(repo.id)
        scheduleWorktreePathIndexRebuild()
        return repo
    }

    @discardableResult
    func ensureMainWorktree(at path: URL) -> Worktree {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let existingIndex = repos.firstIndex(where: {
            $0.repoPath.standardizedFileURL == normalizedPath || $0.stableKey == incomingStableKey
        }) {
            unavailableRepoIds.remove(repos[existingIndex].id)
            if let mainWorktree = repos[existingIndex].worktrees.first(where: \.isMainWorktree) {
                return mainWorktree
            }
            if let firstWorktree = repos[existingIndex].worktrees.first {
                return firstWorktree
            }

            let repairedWorktree = Worktree(
                repoId: repos[existingIndex].id,
                name: normalizedPath.lastPathComponent,
                path: normalizedPath,
                isMainWorktree: true
            )
            repos[existingIndex].name = normalizedPath.lastPathComponent
            repos[existingIndex].repoPath = normalizedPath
            repos[existingIndex].worktrees = [repairedWorktree]
            scheduleWorktreePathIndexRebuild()
            return repairedWorktree
        }

        let repo = addRepo(at: normalizedPath)
        return repo.worktrees[0]
    }

    func removeRepo(_ repoId: UUID) {
        guard repos.contains(where: { $0.id == repoId }) else { return }
        repos.removeAll { $0.id == repoId }
        unavailableRepoIds.remove(repoId)
        scheduleWorktreePathIndexRebuild()
    }

    func markRepoUnavailable(_ repoId: UUID) {
        guard repos.contains(where: { $0.id == repoId }) else { return }
        unavailableRepoIds.insert(repoId)
    }

    func markRepoAvailable(_ repoId: UUID) {
        unavailableRepoIds.remove(repoId)
    }

    func isRepoUnavailable(_ repoId: UUID) -> Bool {
        unavailableRepoIds.contains(repoId)
    }

    @discardableResult
    func addWatchedPath(_ path: URL) -> WatchedPath? {
        let normalizedPath = path.standardizedFileURL
        let key = StableKey.fromPath(normalizedPath)
        guard !watchedPaths.contains(where: { $0.stableKey == key }) else {
            return watchedPaths.first { $0.stableKey == key }
        }
        let watchedPath = WatchedPath(path: normalizedPath)
        watchedPaths.append(watchedPath)
        return watchedPath
    }

    func removeWatchedPath(_ id: UUID) {
        watchedPaths.removeAll { $0.id == id }
    }

    @discardableResult
    func reassociateRepo(_ repoId: UUID, to newPath: URL, discoveredWorktrees: [Worktree]) -> Set<UUID> {
        guard let repoIndex = repos.firstIndex(where: { $0.id == repoId }) else { return [] }
        repos[repoIndex].name = newPath.lastPathComponent
        repos[repoIndex].repoPath = newPath
        unavailableRepoIds.remove(repoId)
        _ = mergeDiscoveredWorktrees(repoId, worktrees: discoveredWorktrees)
        scheduleWorktreePathIndexRebuild()
        return Set(repos[repoIndex].worktrees.map(\.id))
    }

    func reconcileDiscoveredWorktrees(_ repoId: UUID, worktrees: [Worktree]) {
        guard mergeDiscoveredWorktrees(repoId, worktrees: worktrees) else { return }
        scheduleWorktreePathIndexRebuild()
    }

    @discardableResult
    private func mergeDiscoveredWorktrees(_ repoId: UUID, worktrees: [Worktree]) -> Bool {
        guard let index = repos.firstIndex(where: { $0.id == repoId }) else { return false }
        let existing = repos[index].worktrees

        let existingByPath = Dictionary(existing.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let existingMain = existing.first(where: \.isMainWorktree)
        let existingByName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let merged = worktrees.map { discovered -> Worktree in
            if let existing = existingByPath[discovered.path] {
                var updated = existing
                updated.name = discovered.name
                return updated
            }
            if discovered.isMainWorktree, let existingMain {
                return Worktree(
                    id: existingMain.id,
                    repoId: repoId,
                    name: discovered.name,
                    path: discovered.path,
                    isMainWorktree: discovered.isMainWorktree
                )
            }
            if let matched = existingByName[discovered.name] {
                return Worktree(
                    id: matched.id,
                    repoId: repoId,
                    name: discovered.name,
                    path: discovered.path,
                    isMainWorktree: discovered.isMainWorktree
                )
            }
            return discovered
        }

        guard merged != existing else { return false }
        repos[index].worktrees = merged
        return true
    }

    private func scheduleWorktreePathIndexRebuild() {
        guard deferredWorktreePathIndexRebuildDepth == 0 else {
            deferredWorktreePathIndexRebuildNeeded = true
            return
        }
        rebuildWorktreePathIndexAndBumpGeneration()
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
                    repo: repo,
                    worktree: item.worktree,
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
