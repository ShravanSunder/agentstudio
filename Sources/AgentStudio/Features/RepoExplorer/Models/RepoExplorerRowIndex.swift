import Foundation

struct RepoExplorerResolvedWorktreeContext: Sendable {
    let rowId: String
    let group: RepoPresentationGroup
    let repo: RepoPresentationItem
    let worktree: Worktree
    let placementContext: RepoExplorerPlacementContext?
}

struct RepoExplorerRowIndex: Equatable, Sendable {
    let projection: RepoExplorerSidebarProjection
    let entries: [RepoExplorerListEntry]

    private let groupsById: [String: RepoPresentationGroup]
    private let projectedRowsByRowId: [String: RepoExplorerProjectedWorktreeRow]

    init(
        projection: RepoExplorerSidebarProjection,
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) {
        let projectedRowsByGroupId = Self.projectedRowsByGroupId(for: projection)
        self.projection = projection
        self.entries = Self.buildListEntries(
            groups: projection.resolvedGroups,
            projectedRowsByGroupId: projectedRowsByGroupId,
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
        self.groupsById = Dictionary(uniqueKeysWithValues: projection.resolvedGroups.map { ($0.id, $0) })
        self.projectedRowsByRowId = Dictionary(
            uniqueKeysWithValues: projectedRowsByGroupId.values.flatMap { rows in
                rows.map { ($0.rowId, $0) }
            })
    }

    func resolve(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID,
        rowId: String
    ) -> RepoExplorerResolvedWorktreeContext? {
        guard
            let group = groupsById[groupId],
            let projectedRow = projectedRowsByRowId[rowId]
        else { return nil }
        guard projectedRow.groupId == groupId, projectedRow.repo.id == repoId, projectedRow.worktree.id == worktreeId
        else { return nil }
        return RepoExplorerResolvedWorktreeContext(
            rowId: rowId,
            group: group,
            repo: projectedRow.repo,
            worktree: projectedRow.worktree,
            placementContext: projectedRow.placementContext
        )
    }

    static func buildListEntries(
        groups: [RepoPresentationGroup],
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        buildListEntries(
            groups: groups,
            projectedRowsByGroupId: projectedRowsByGroupId(for: groups),
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
    }

    static func buildListEntries(
        groups: [RepoPresentationGroup],
        projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]],
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        var entries: [RepoExplorerListEntry] = []

        for group in groups {
            entries.append(.resolvedGroupHeader(group))

            let shouldExpandGroup = isFiltering || expandedGroupIds.contains(group.id)
            guard shouldExpandGroup else { continue }

            for row in projectedRowsByGroupId[group.id] ?? [] {
                entries.append(
                    .resolvedWorktreeRow(
                        groupId: group.id,
                        repoId: row.repo.id,
                        worktreeId: row.worktree.id,
                        rowId: row.rowId
                    )
                )
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

    private static func projectedRowsByGroupId(
        for projection: RepoExplorerSidebarProjection
    ) -> [String: [RepoExplorerProjectedWorktreeRow]] {
        if !projection.worktreeRowsByGroupId.isEmpty {
            return projection.worktreeRowsByGroupId
        }
        return projectedRowsByGroupId(for: projection.resolvedGroups)
    }

    private static func projectedRowsByGroupId(
        for groups: [RepoPresentationGroup]
    ) -> [String: [RepoExplorerProjectedWorktreeRow]] {
        Dictionary(
            uniqueKeysWithValues: groups.map { group in
                let rows = group.repos.flatMap { repo in
                    sortedWorktrees(for: repo).map { worktree in
                        RepoExplorerProjectedWorktreeRow(
                            groupId: group.id,
                            repo: repo,
                            worktree: worktree,
                            rowId: "worktree:\(group.id):\(repo.id.uuidString):\(worktree.id.uuidString):inactive",
                            placementContext: nil
                        )
                    }
                }
                return (group.id, rows)
            })
    }
}
