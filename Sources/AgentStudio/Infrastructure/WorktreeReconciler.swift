import Foundation

struct RemovedWorktreeEntry: Sendable, Equatable {
    let id: UUID
    let path: URL
}

struct WorktreeTopologyDelta: Sendable, Equatable {
    let repoId: UUID
    let addedWorktreeIds: [UUID]
    let removedWorktrees: [RemovedWorktreeEntry]
    let preservedWorktreeIds: [UUID]
    let didChange: Bool
    let traceId: UUID?
}

enum WorktreeReconciler {
    static func reconcile(
        repoId: UUID,
        existing: [Worktree],
        discovered: [Worktree],
        traceId: UUID? = nil
    ) -> (merged: [Worktree], delta: WorktreeTopologyDelta) {
        let existingByPath = Dictionary(
            existing.map { ($0.path.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingMainWorktree = existing.first(where: \.isMainWorktree)
        let existingByName = Dictionary(
            existing.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var preservedWorktreeIds: [UUID] = []
        var addedWorktreeIds: [UUID] = []

        let merged = discovered.map { discoveredWorktree -> Worktree in
            let standardizedPath = discoveredWorktree.path.standardizedFileURL
            if let existingByPathMatch = existingByPath[standardizedPath] {
                preservedWorktreeIds.append(existingByPathMatch.id)

                var updatedWorktree = existingByPathMatch
                updatedWorktree.name = discoveredWorktree.name
                updatedWorktree.path = discoveredWorktree.path
                updatedWorktree.isMainWorktree = discoveredWorktree.isMainWorktree
                return updatedWorktree
            }

            if discoveredWorktree.isMainWorktree, let existingMainWorktree {
                preservedWorktreeIds.append(existingMainWorktree.id)
                return Worktree(
                    id: existingMainWorktree.id,
                    repoId: repoId,
                    name: discoveredWorktree.name,
                    path: discoveredWorktree.path,
                    isMainWorktree: true
                )
            }

            if let existingByNameMatch = existingByName[discoveredWorktree.name] {
                preservedWorktreeIds.append(existingByNameMatch.id)
                return Worktree(
                    id: existingByNameMatch.id,
                    repoId: repoId,
                    name: discoveredWorktree.name,
                    path: discoveredWorktree.path,
                    isMainWorktree: discoveredWorktree.isMainWorktree
                )
            }

            let addedWorktree = Worktree(
                repoId: repoId,
                name: discoveredWorktree.name,
                path: discoveredWorktree.path,
                isMainWorktree: discoveredWorktree.isMainWorktree
            )
            addedWorktreeIds.append(addedWorktree.id)
            return addedWorktree
        }

        let preservedWorktreeIdSet = Set(preservedWorktreeIds)
        let removedWorktrees =
            existing
            .filter { !preservedWorktreeIdSet.contains($0.id) }
            .map { RemovedWorktreeEntry(id: $0.id, path: $0.path) }

        let delta = WorktreeTopologyDelta(
            repoId: repoId,
            addedWorktreeIds: addedWorktreeIds,
            removedWorktrees: removedWorktrees,
            preservedWorktreeIds: preservedWorktreeIds,
            didChange: merged != existing,
            traceId: traceId
        )

        return (merged: merged, delta: delta)
    }
}
