import AgentStudioCore
import Foundation

extension WorkspaceCacheCoordinator {
    static func buildDiscoveredWorktreeList(
        clonePath: URL,
        linkedPaths: [URL],
        stableIdentity: DiscoveredRepoStableIdentity
    ) -> RepositoryScannedWorktrees {
        let normalizedClonePath = clonePath.standardizedFileURL
        let normalizedLinkedPaths = Array(Set(linkedPaths.map(\.standardizedFileURL)))
            .filter { $0 != normalizedClonePath }
            .sorted(by: sortPaths)

        let mainWorktree = RepositoryScannedMainWorktree(
            name: normalizedClonePath.lastPathComponent,
            path: normalizedClonePath,
            stableKey: stableIdentity.worktreeStableKeysByPath[normalizedClonePath]
        )
        let linkedWorktrees = normalizedLinkedPaths.map { linkedPath in
            RepositoryScannedLinkedWorktree(
                name: linkedPath.lastPathComponent,
                path: linkedPath,
                stableKey: stableIdentity.worktreeStableKeysByPath[linkedPath]
            )
        }
        return RepositoryScannedWorktrees(main: mainWorktree, linked: linkedWorktrees)
    }

    static func sortPaths(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}
