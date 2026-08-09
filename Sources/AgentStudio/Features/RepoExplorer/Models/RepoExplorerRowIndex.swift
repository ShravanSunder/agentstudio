import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

struct RepoExplorerResolvedWorktreeContext: Sendable {
    let rowId: String
    let group: RepoPresentationGroup
    let repo: RepoPresentationItem
    let worktree: Worktree
    let checkoutColorHex: String
    let placementContext: RepoExplorerPlacementContext?
}

struct RepoExplorerResolvedPaneContext: Sendable {
    let rowId: String
    let group: RepoPresentationGroup
    let destination: RepoExplorerPaneDestination
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
    private let projectedPaneRowsByRowId: [String: RepoExplorerProjectedPaneRow]

    init(
        projection: RepoExplorerSidebarProjection,
        collapsedGroupIds: Set<String>,
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
            self.projectedPaneRowsByRowId = [:]
            return
        }

        self.entries = Self.buildSectionedListEntries(
            sections: projection.sections,
            projectedRowsByGroupId: projectedRowsByGroupId,
            projectedPaneRowsByGroupId: projection.paneRowsByGroupId,
            collapsedGroupIds: collapsedGroupIds,
            isFiltering: isFiltering
        )
        self.state = .ready
        self.groupsById = Dictionary(uniqueKeysWithValues: projection.resolvedGroups.map { ($0.id, $0) })
        self.projectedRowsByRowId = Dictionary(
            uniqueKeysWithValues: projectedRowsByGroupId.values.flatMap { rows in
                rows.map { ($0.rowId, $0) }
            })
        self.projectedPaneRowsByRowId = Dictionary(
            uniqueKeysWithValues: projection.paneRowsByGroupId.values.flatMap { rows in
                rows.map { ($0.rowId, $0) }
            })
        self.worktreeIds =
            projectedRowsByGroupId.values.flatMap { rows in
                rows.map(\.worktree.id)
            } + projection.paneRowsByGroupId.values.flatMap { rows in rows.map(\.destination.worktreeId) }
    }

    func resolvePane(
        groupId: String,
        repoId: UUID,
        paneId: UUID,
        rowId: String
    ) -> RepoExplorerResolvedPaneContext? {
        guard
            let group = groupsById[groupId],
            let projectedRow = projectedPaneRowsByRowId[rowId]
        else { return nil }
        guard
            projectedRow.groupId == groupId,
            projectedRow.repoId == repoId,
            projectedRow.destination.paneId == paneId
        else { return nil }
        return RepoExplorerResolvedPaneContext(
            rowId: rowId,
            group: group,
            destination: projectedRow.destination
        )
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
        collapsedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        buildListEntries(
            groups: groups,
            projectedRowsByGroupId: projectedRowsByGroupId(for: groups),
            projectedPaneRowsByGroupId: [:],
            collapsedGroupIds: collapsedGroupIds,
            isFiltering: isFiltering
        )
    }

    static func buildListEntries(
        groups: [RepoPresentationGroup],
        projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]],
        projectedPaneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:],
        collapsedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        var entries: [RepoExplorerListEntry] = []

        for group in groups {
            entries.append(.resolvedGroupHeader(group))

            let shouldExpandGroup = isFiltering || !collapsedGroupIds.contains(group.id)
            guard shouldExpandGroup else { continue }

            let worktreeRows = projectedRowsByGroupId[group.id] ?? []
            if group.id.hasPrefix("tab:") {
                appendTabSectionEntries(
                    groupId: group.id,
                    worktreeRows: worktreeRows,
                    entries: &entries
                )
            } else {
                appendWorktreeRows(
                    groupId: group.id,
                    worktreeRows: worktreeRows,
                    entries: &entries
                )
            }
            for row in projectedPaneRowsByGroupId[group.id] ?? [] {
                entries.append(
                    .resolvedPaneRow(
                        groupId: group.id,
                        identity: RepoExplorerPaneListEntryIdentity(
                            repoId: row.repoId,
                            worktreeId: row.destination.worktreeId,
                            paneId: row.destination.paneId
                        ),
                        rowId: row.rowId
                    )
                )
            }
        }

        return entries
    }

    private static func appendTabSectionEntries(
        groupId: String,
        worktreeRows: [RepoExplorerProjectedWorktreeRow],
        entries: inout [RepoExplorerListEntry]
    ) {
        for (kind, rows) in [
            (RepoExplorerSidebarSectionKind.favorites, worktreeRows.filter { $0.repo.isFavorite }),
            (RepoExplorerSidebarSectionKind.repositories, worktreeRows.filter { !$0.repo.isFavorite }),
        ] where !rows.isEmpty {
            entries.append(.groupSectionHeader(groupId: groupId, kind: kind))
            appendWorktreeRows(groupId: groupId, worktreeRows: rows, entries: &entries)
        }
    }

    private static func appendWorktreeRows(
        groupId: String,
        worktreeRows: [RepoExplorerProjectedWorktreeRow],
        entries: inout [RepoExplorerListEntry]
    ) {
        entries.append(
            contentsOf: worktreeRows.map { row in
                .resolvedWorktreeRow(
                    groupId: groupId,
                    repoId: row.repo.id,
                    worktreeId: row.worktree.id,
                    rowId: row.rowId
                )
            }
        )
    }

    private static func buildSectionedListEntries(
        sections: [RepoExplorerSidebarSection],
        projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]],
        projectedPaneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]],
        collapsedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        sections.flatMap { section in
            var entries: [RepoExplorerListEntry] = [.sectionHeader(section.kind)]
            entries.append(
                contentsOf: buildListEntries(
                    groups: section.resolvedGroups,
                    projectedRowsByGroupId: projectedRowsByGroupId,
                    projectedPaneRowsByGroupId: projectedPaneRowsByGroupId,
                    collapsedGroupIds: collapsedGroupIds,
                    isFiltering: isFiltering
                )
            )
            if !section.loadingRepos.isEmpty {
                entries.append(.loadingSectionHeader(section.kind))
                entries.append(
                    contentsOf: section.loadingRepos.map {
                        .loadingRepoRow(section: section.kind, repo: $0)
                    }
                )
            }
            return entries
        }
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
        if !projection.paneRowsByGroupId.isEmpty {
            return [:]
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
