import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceCatalogAtom {
    private(set) var workspaceId = UUID()
    private(set) var workspaceName: String = "Default Workspace"
    private(set) var repos: [Repo] = []
    private(set) var watchedPaths: [WatchedPath] = []
    private(set) var unavailableRepoIds: Set<UUID> = []
    private(set) var sidebarWidth: CGFloat = 250
    private(set) var windowFrame: CGRect?
    private(set) var createdAt = Date()
    private(set) var updatedAt = Date()

    func restoreFromPersistence(
        _ state: WorkspacePersistor.PersistableState,
        runtimeRepos: [Repo]
    ) {
        workspaceId = state.id
        workspaceName = state.name
        repos = runtimeRepos
        watchedPaths = state.watchedPaths
        unavailableRepoIds = state.unavailableRepoIds
        sidebarWidth = state.sidebarWidth
        windowFrame = state.windowFrame
        createdAt = state.createdAt
        updatedAt = state.updatedAt
    }

    func noteStateMutation() {
        updatedAt = Date()
    }

    func didPersist(at date: Date) {
        updatedAt = date
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

        struct MatchCandidate {
            let repo: Repo
            let worktree: Worktree
            let normalizedWorktreePath: String
            let repoWorktreeCount: Int
            let repoPathMatchesWorktree: Bool
            let isMainWorktree: Bool
            let stableTieBreaker: String
        }

        let normalizedCWD = cwd.standardizedFileURL.path
        let candidates = repos.flatMap { repo -> [MatchCandidate] in
            let repoPathMatchesAnyWorktree = repo.worktrees.contains {
                $0.path.standardizedFileURL == repo.repoPath.standardizedFileURL
            }
            return repo.worktrees.compactMap { worktree in
                let normalizedWorktreePath = worktree.path.standardizedFileURL.path
                guard
                    normalizedCWD == normalizedWorktreePath
                        || normalizedCWD.hasPrefix(normalizedWorktreePath + "/")
                else { return nil }

                return MatchCandidate(
                    repo: repo,
                    worktree: worktree,
                    normalizedWorktreePath: normalizedWorktreePath,
                    repoWorktreeCount: repo.worktrees.count,
                    repoPathMatchesWorktree: repoPathMatchesAnyWorktree
                        && repo.repoPath.standardizedFileURL == worktree.path.standardizedFileURL,
                    isMainWorktree: worktree.isMainWorktree,
                    stableTieBreaker: "\(repo.id.uuidString)|\(worktree.id.uuidString)"
                )
            }
        }

        guard
            let best = candidates.max(by: { lhs, rhs in
                if lhs.normalizedWorktreePath.count != rhs.normalizedWorktreePath.count {
                    return lhs.normalizedWorktreePath.count < rhs.normalizedWorktreePath.count
                }
                if lhs.repoWorktreeCount != rhs.repoWorktreeCount {
                    return lhs.repoWorktreeCount > rhs.repoWorktreeCount
                }
                if lhs.repoPathMatchesWorktree != rhs.repoPathMatchesWorktree {
                    return !lhs.repoPathMatchesWorktree && rhs.repoPathMatchesWorktree
                }
                if lhs.isMainWorktree != rhs.isMainWorktree {
                    return lhs.isMainWorktree && !rhs.isMainWorktree
                }
                return lhs.stableTieBreaker > rhs.stableTieBreaker
            })
        else {
            return nil
        }

        return (best.repo, best.worktree)
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
        return repo
    }

    func removeRepo(_ repoId: UUID) {
        repos.removeAll { $0.id == repoId }
        unavailableRepoIds.remove(repoId)
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
        reconcileDiscoveredWorktrees(repoId, worktrees: discoveredWorktrees)
        return Set(repos[repoIndex].worktrees.map(\.id))
    }

    func reconcileDiscoveredWorktrees(_ repoId: UUID, worktrees: [Worktree]) {
        guard let index = repos.firstIndex(where: { $0.id == repoId }) else { return }
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

        guard merged != existing else { return }
        repos[index].worktrees = merged
    }

    func setSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
    }

    func setWindowFrame(_ frame: CGRect?) {
        windowFrame = frame
    }
}
