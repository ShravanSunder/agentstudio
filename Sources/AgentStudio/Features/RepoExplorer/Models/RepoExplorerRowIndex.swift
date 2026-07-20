import Foundation

struct RepoExplorerResolvedWorktreeContext: Sendable {
    let rowId: String
    let group: RepoPresentationGroup
    let repo: RepoPresentationItem
    let worktree: Worktree
    let checkoutColorHex: String
    let placementContext: RepoExplorerPlacementContext?
}

struct RepoExplorerWorktreeIdentityClaim: Equatable, Sendable {
    let repoId: UUID
    let stableKey: String
    let path: URL
}

struct RepoExplorerDuplicateWorktreeIdentity: Equatable, Sendable {
    let worktreeId: UUID
    let claims: [RepoExplorerWorktreeIdentityClaim]
}

enum RepoExplorerTopologyFault: Equatable, Sendable {
    case duplicateWorktreeIdentities([RepoExplorerDuplicateWorktreeIdentity])

    var duplicateIdentityCount: Int {
        switch self {
        case .duplicateWorktreeIdentities(let duplicates):
            duplicates.count
        }
    }

}

struct RepoExplorerTopologyFaultDetector {
    private var claimsByWorktreeId: [UUID: [RepoExplorerWorktreeIdentityClaim]] = [:]

    mutating func observe(_ repo: RepoPresentationItem) {
        for worktree in repo.worktrees {
            claimsByWorktreeId[worktree.id, default: []].append(
                RepoExplorerWorktreeIdentityClaim(
                    repoId: repo.id,
                    stableKey: worktree.stableKey,
                    path: worktree.path
                )
            )
        }
    }

    var fault: RepoExplorerTopologyFault? {
        var duplicateIdentities: [RepoExplorerDuplicateWorktreeIdentity] = []
        for (worktreeId, claims) in claimsByWorktreeId where claims.count > 1 {
            duplicateIdentities.append(
                RepoExplorerDuplicateWorktreeIdentity(
                    worktreeId: worktreeId,
                    claims: claims.sorted(by: claimPrecedes)
                )
            )
        }
        duplicateIdentities.sort { $0.worktreeId.uuidString < $1.worktreeId.uuidString }

        guard !duplicateIdentities.isEmpty else { return nil }
        return .duplicateWorktreeIdentities(duplicateIdentities)
    }

    private func claimPrecedes(
        _ lhs: RepoExplorerWorktreeIdentityClaim,
        _ rhs: RepoExplorerWorktreeIdentityClaim
    ) -> Bool {
        if lhs.repoId != rhs.repoId {
            return lhs.repoId.uuidString < rhs.repoId.uuidString
        }
        if lhs.path != rhs.path {
            return lhs.path.path < rhs.path.path
        }
        return lhs.stableKey < rhs.stableKey
    }
}

enum RepoExplorerRowIndexState: Equatable, Sendable {
    case ready
    case degraded(RepoExplorerTopologyFault)
}

struct RepoExplorerRowIndex: Equatable, Sendable {
    let projection: RepoExplorerSidebarProjection
    let entries: [RepoExplorerListEntry]
    let state: RepoExplorerRowIndexState
    let worktreeIds: [UUID]

    private let groupsById: [String: RepoPresentationGroup]
    private let projectedRowsByRowId: [String: RepoExplorerProjectedWorktreeRow]

    init(
        projection: RepoExplorerSidebarProjection,
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) {
        let projectedRowsByGroupId = Self.projectedRowsByGroupId(for: projection)
        self.projection = projection

        if case .degraded(let topologyFault) = projection {
            self.entries = [.topologyFault(topologyFault)]
            self.state = .degraded(topologyFault)
            self.worktreeIds = []
            self.groupsById = [:]
            self.projectedRowsByRowId = [:]
            return
        }

        self.entries = Self.buildListEntries(
            groups: projection.resolvedGroups,
            projectedRowsByGroupId: projectedRowsByGroupId,
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
        self.state = .ready
        self.groupsById = Dictionary(uniqueKeysWithValues: projection.resolvedGroups.map { ($0.id, $0) })
        self.projectedRowsByRowId = Dictionary(
            uniqueKeysWithValues: projectedRowsByGroupId.values.flatMap { rows in
                rows.map { ($0.rowId, $0) }
            })
        self.worktreeIds = projectedRowsByGroupId.values.flatMap { rows in
            rows.map(\.worktree.id)
        }
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
            checkoutColorHex: projectedRow.checkoutColorHex,
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
                    repo.worktrees.map { worktree in
                        RepoExplorerProjectedWorktreeRow(
                            groupId: group.id,
                            repo: repo,
                            worktree: worktree,
                            rowId: "worktree:\(group.id):\(repo.id.uuidString):\(worktree.id.uuidString):inactive",
                            checkoutColorHex: RepoPresentationColoring.checkoutColorHex(
                                for: repo,
                                in: group
                            ),
                            placementContext: nil
                        )
                    }
                }
                return (group.id, rows)
            })
    }
}
