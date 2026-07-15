import Foundation

struct RepoExplorerResolvedWorktreeContext {
    let group: RepoPresentationGroup
    let repo: RepoPresentationItem
    let worktree: Worktree
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

struct RepoExplorerRowIndex {
    let projection: RepoExplorerSidebarProjection
    let entries: [RepoExplorerListEntry]
    let state: RepoExplorerRowIndexState
    let worktreeIds: [UUID]

    private let groupsById: [String: RepoPresentationGroup]
    private let reposByKey: [RepoKey: RepoPresentationItem]
    private let worktreesByKey: [WorktreeKey: Worktree]

    init(
        projection: RepoExplorerSidebarProjection,
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) {
        self.projection = projection

        if case .degraded(let topologyFault) = projection {
            self.entries = [.topologyFault(topologyFault)]
            self.state = .degraded(topologyFault)
            self.worktreeIds = []
            self.groupsById = [:]
            self.reposByKey = [:]
            self.worktreesByKey = [:]
            return
        }

        self.entries = Self.buildListEntries(
            groups: projection.resolvedGroups,
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
        self.state = .ready
        self.groupsById = Dictionary(uniqueKeysWithValues: projection.resolvedGroups.map { ($0.id, $0) })

        var reposByKey: [RepoKey: RepoPresentationItem] = [:]
        var worktreesByKey: [WorktreeKey: Worktree] = [:]
        var worktreeIds: [UUID] = []
        for group in projection.resolvedGroups {
            for repo in group.repos {
                reposByKey[RepoKey(groupId: group.id, repoId: repo.id)] = repo
                for worktree in repo.worktrees {
                    worktreeIds.append(worktree.id)
                    worktreesByKey[
                        WorktreeKey(groupId: group.id, repoId: repo.id, worktreeId: worktree.id)
                    ] = worktree
                }
            }
        }
        self.reposByKey = reposByKey
        self.worktreesByKey = worktreesByKey
        self.worktreeIds = worktreeIds
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
