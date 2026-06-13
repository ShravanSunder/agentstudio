import Foundation

struct RepoExplorerResolvedWorktreeContext {
    let group: RepoPresentationGroup
    let repo: RepoPresentationItem
    let worktree: Worktree
}

struct RepoExplorerRowIndex {
    let projection: RepoExplorerSidebarProjection
    let entries: [RepoExplorerListEntry]

    private let groupsById: [String: RepoPresentationGroup]
    private let reposByKey: [RepoKey: RepoPresentationItem]
    private let worktreesByKey: [WorktreeKey: Worktree]

    init(
        projection: RepoExplorerSidebarProjection,
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) {
        self.projection = projection
        self.entries = Self.buildListEntries(
            groups: projection.resolvedGroups,
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
        self.groupsById = Dictionary(uniqueKeysWithValues: projection.resolvedGroups.map { ($0.id, $0) })

        var reposByKey: [RepoKey: RepoPresentationItem] = [:]
        var worktreesByKey: [WorktreeKey: Worktree] = [:]
        for group in projection.resolvedGroups {
            for repo in group.repos {
                reposByKey[RepoKey(groupId: group.id, repoId: repo.id)] = repo
                for worktree in repo.worktrees {
                    worktreesByKey[
                        WorktreeKey(groupId: group.id, repoId: repo.id, worktreeId: worktree.id)
                    ] = worktree
                }
            }
        }
        self.reposByKey = reposByKey
        self.worktreesByKey = worktreesByKey
    }

    func resolve(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID
    ) -> RepoExplorerResolvedWorktreeContext? {
        guard
            let group = groupsById[groupId],
            let repo = reposByKey[RepoKey(groupId: groupId, repoId: repoId)],
            let worktree = worktreesByKey[WorktreeKey(groupId: groupId, repoId: repoId, worktreeId: worktreeId)]
        else { return nil }
        return RepoExplorerResolvedWorktreeContext(group: group, repo: repo, worktree: worktree)
    }

    static func buildListEntries(
        groups: [RepoPresentationGroup],
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        var entries: [RepoExplorerListEntry] = []

        for group in groups {
            entries.append(.resolvedGroupHeader(group))

            let shouldExpandGroup = isFiltering || expandedGroupIds.contains(group.id)
            guard shouldExpandGroup else { continue }

            for repo in group.repos {
                for worktree in sortedWorktrees(for: repo) {
                    entries.append(
                        .resolvedWorktreeRow(
                            groupId: group.id,
                            repoId: repo.id,
                            worktreeId: worktree.id
                        )
                    )
                }
            }
        }

        return entries
    }

    static func sortedWorktrees(for repo: RepoPresentationItem) -> [Worktree] {
        repo.worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private struct RepoKey: Hashable {
        let groupId: String
        let repoId: UUID
    }

    private struct WorktreeKey: Hashable {
        let groupId: String
        let repoId: UUID
        let worktreeId: UUID
    }
}
