import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

struct RepoExplorerResolvedWorktreeContext: Sendable {
    let rowId: RepoExplorerRowID
    let group: RepoPresentationGroup
    let repo: RepoPresentationItem
    let worktree: Worktree
    let checkoutColorHex: String
    let placementContext: RepoExplorerPlacementContext?
}

struct RepoExplorerResolvedPaneContext: Sendable {
    let rowId: RepoExplorerRowID
    let group: RepoPresentationGroup
    let row: RepoExplorerProjectedPaneRow
    let destination: RepoExplorerProjectedPaneDestination
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
                    stableKey: repo.worktreeStableKeysByID[worktree.id] ?? "",
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
    let collapsedGroupIds: Set<String>
    let isFiltering: Bool

    private let groupsById: [String: RepoPresentationGroup]
    private let projectedRowsByRowId: [RepoExplorerRowID: RepoExplorerProjectedWorktreeRow]
    private let projectedPaneRowsByRowId: [RepoExplorerRowID: RepoExplorerProjectedPaneRow]

    init(
        projection: RepoExplorerSidebarProjection,
        collapsedGroupIds: Set<String>,
        isFiltering: Bool
    ) {
        let projectedRowsByGroupId = Self.projectedRowsByGroupId(for: projection)
        self.projection = projection
        self.collapsedGroupIds = collapsedGroupIds
        self.isFiltering = isFiltering

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
                rows.map { row in
                    (
                        RepoExplorerRowID.worktree(
                            groupID: row.groupId,
                            repoID: row.repo.id,
                            worktreeID: row.worktree.id
                        ),
                        row
                    )
                }
            })
        self.projectedPaneRowsByRowId = Dictionary(
            uniqueKeysWithValues: projection.paneRowsByGroupId.values.flatMap { rows in
                rows.map { row in
                    (
                        Self.paneRowID(for: row),
                        row
                    )
                }
            })
        self.worktreeIds =
            projectedRowsByGroupId.values.flatMap { rows in
                rows.map(\.worktree.id)
            }
            + projection.paneRowsByGroupId.values.flatMap { rows in
                rows.compactMap(\.worktreeId)
            }
    }

    func resolvePane(
        groupId: String,
        repoId: UUID?,
        paneId: UUID,
        rowId: RepoExplorerRowID
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
            row: projectedRow,
            destination: projectedRow.destination
        )
    }

    func resolve(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID,
        rowId: RepoExplorerRowID
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
            appendWorktreeRows(
                groupId: group.id,
                worktreeRows: worktreeRows,
                entries: &entries
            )
            for row in projectedPaneRowsByGroupId[group.id] ?? [] {
                entries.append(
                    .resolvedPaneRow(
                        groupId: group.id,
                        identity: RepoExplorerPaneListEntryIdentity(
                            repoId: row.repoId,
                            worktreeId: row.worktreeId,
                            paneId: row.destination.paneId
                        ),
                        rowId: paneRowID(for: row)
                    )
                )
            }
        }

        return entries
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
                    rowId: .worktree(
                        groupID: row.groupId,
                        repoID: row.repo.id,
                        worktreeID: row.worktree.id
                    )
                )
            }
        )
    }

    private static func paneRowID(
        for row: RepoExplorerProjectedPaneRow
    ) -> RepoExplorerRowID {
        switch row.membershipOwner {
        case .tab:
            return .tabPane(groupID: row.groupId, paneID: row.destination.paneId)
        case .association:
            guard let repoId = row.repoId, let worktreeId = row.worktreeId else {
                preconditionFailure("Association-owned pane row requires repository enrichment")
            }
            return .associatedPane(
                groupID: row.groupId,
                repoID: repoId,
                worktreeID: worktreeId,
                paneID: row.destination.paneId
            )
        }
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
            entries.append(
                contentsOf: section.unassociatedPaneDestinations.map {
                    .unassociatedPaneRow($0)
                }
            )
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

    func isGroupExpanded(_ groupID: String) -> Bool {
        isFiltering || !collapsedGroupIds.contains(groupID)
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
