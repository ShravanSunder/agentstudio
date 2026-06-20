import Foundation

struct RepoExplorerSidebarProjection: Equatable, Sendable {
    let resolvedGroups: [RepoPresentationGroup]
    let worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]
    let loadingRepos: [RepoPresentationItem]
    let showsNoResults: Bool

    init(
        resolvedGroups: [RepoPresentationGroup],
        worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:],
        loadingRepos: [RepoPresentationItem],
        showsNoResults: Bool
    ) {
        self.resolvedGroups = resolvedGroups
        self.worktreeRowsByGroupId = worktreeRowsByGroupId
        self.loadingRepos = loadingRepos
        self.showsNoResults = showsNoResults
    }
}

struct RepoExplorerPlacementContext: Equatable, Sendable {
    let paneId: UUID
    let tabId: UUID
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool

    var displayText: String {
        let paneTitle = "Pane \(paneIndexInTab + 1)"
        return isActiveInTab ? "\(paneTitle) active" : paneTitle
    }
}

struct RepoExplorerProjectedWorktreeRow: Equatable, Sendable {
    let groupId: String
    let repo: RepoPresentationItem
    let worktree: Worktree
    let rowId: String
    let placementContext: RepoExplorerPlacementContext?
}

enum RepoExplorerProjection {
    private struct PlacementEntry {
        let repo: RepoPresentationItem
        let worktree: Worktree
        let location: WorkspacePaneLocation?
    }

    static func project(_ snapshot: RepoExplorerSnapshot) -> RepoExplorerSidebarProjection {
        let resolvedRepos = resolvedRepos(snapshot.repos, enrichmentByRepoId: snapshot.repoEnrichmentSnapshotByRepoId)
        let loadingRepos = loadingRepos(snapshot.repos, enrichmentByRepoId: snapshot.repoEnrichmentSnapshotByRepoId)
        let filteredResolvedRepos = RepoExplorerFilter.filter(repos: resolvedRepos, query: snapshot.query)
        let filteredLoadingRepos = filterLoadingRepos(
            loadingRepos,
            query: snapshot.query,
            sortOrder: snapshot.sortOrder
        )
        let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
            repos: filteredResolvedRepos,
            repoEnrichmentByRepoId: snapshot.repoEnrichmentSnapshotByRepoId
        )
        let resolvedGroups: [RepoPresentationGroup]
        let projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]
        switch snapshot.groupingMode {
        case .repo:
            resolvedGroups = repoIdentityGroups(
                repos: filteredResolvedRepos,
                metadataByRepoId: repoMetadataById,
                sortOrder: snapshot.sortOrder
            )
            projectedRowsByGroupId = worktreeRowsByGroupId(from: resolvedGroups)
        case .pane:
            let placementProjection = placementGroups(
                repos: filteredResolvedRepos,
                locationsByWorktreeId: snapshot.paneLocationsByWorktreeId,
                mode: .pane,
                sortOrder: snapshot.sortOrder
            )
            resolvedGroups = placementProjection.groups
            projectedRowsByGroupId = placementProjection.worktreeRowsByGroupId
        case .tab:
            let placementProjection = placementGroups(
                repos: filteredResolvedRepos,
                locationsByWorktreeId: snapshot.paneLocationsByWorktreeId,
                mode: .tab,
                sortOrder: snapshot.sortOrder
            )
            resolvedGroups = placementProjection.groups
            projectedRowsByGroupId = placementProjection.worktreeRowsByGroupId
        }

        return RepoExplorerSidebarProjection(
            resolvedGroups: resolvedGroups,
            worktreeRowsByGroupId: projectedRowsByGroupId,
            loadingRepos: filteredLoadingRepos,
            showsNoResults: !snapshot.query.isEmpty && resolvedGroups.isEmpty && filteredLoadingRepos.isEmpty
        )
    }

    static func resolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return true
            case .awaitingOrigin, .none:
                return false
            }
        }
    }

    static func loadingRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return false
            case .awaitingOrigin, .none:
                return true
            }
        }
    }

    private static func filterLoadingRepos(
        _ repos: [RepoPresentationItem],
        query: String,
        sortOrder: RepoExplorerSortOrder
    ) -> [RepoPresentationItem] {
        let filteredRepos: [RepoPresentationItem]
        if query.isEmpty {
            filteredRepos = repos
        } else {
            filteredRepos = repos.filter { repo in
                repo.name.localizedCaseInsensitiveContains(query)
            }
        }

        return sortedRepos(filteredRepos, sortOrder: sortOrder)
    }

    private static func repoIdentityGroups(
        repos: [RepoPresentationItem],
        metadataByRepoId: [UUID: RepoIdentityMetadata],
        sortOrder: RepoExplorerSortOrder
    ) -> [RepoPresentationGroup] {
        repos.compactMap { repo in
            guard !repo.worktrees.isEmpty else { return nil }
            let metadata = metadataByRepoId[repo.id]
            var projectedRepo = repo
            projectedRepo.worktrees = sortedWorktrees(repo.worktrees, sortOrder: sortOrder)
            return RepoPresentationGroup(
                id: "repo:\(repo.id.uuidString)",
                repoTitle: metadata?.repoName ?? repo.name,
                organizationName: metadata?.organizationName,
                repos: [projectedRepo]
            )
        }
        .sorted { lhs, rhs in
            if lhs.repos.first?.isFavorite != rhs.repos.first?.isFavorite {
                return lhs.repos.first?.isFavorite == true
            }
            let leftTitle = lhs.organizationName.map { "\(lhs.repoTitle)\($0)" } ?? lhs.repoTitle
            let rightTitle = rhs.organizationName.map { "\(rhs.repoTitle)\($0)" } ?? rhs.repoTitle
            return compare(leftTitle, rightTitle, sortOrder: sortOrder)
        }
    }

    private static func placementGroups(
        repos: [RepoPresentationItem],
        locationsByWorktreeId: [UUID: [WorkspacePaneLocation]],
        mode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder
    ) -> (groups: [RepoPresentationGroup], worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]) {
        let locations = sortedUniqueLocations(locationsByWorktreeId.values.flatMap { $0 })
        let paneOrdinalById = Dictionary(
            uniqueKeysWithValues: locations.enumerated().map { index, location in
                (location.paneId, index + 1)
            })
        let tabOrdinalById = Dictionary(
            uniqueKeysWithValues: sortedUniqueTabIds(locations).enumerated().map { index, tabId in
                (tabId, index + 1)
            })

        var entriesByGroupId: [String: [PlacementEntry]] = [:]
        var groupLabelsById: [String: (title: String, secondary: String?)] = [:]
        var groupOrder: [String] = []
        var paneModeSeenWorktreesByGroup: [String: Set<UUID>] = [:]
        let inactiveGroupId = "\(mode.rawValue):inactive"

        func appendGroupIfNeeded(_ groupId: String, title: String, secondary: String? = nil) {
            guard groupLabelsById[groupId] == nil else { return }
            groupLabelsById[groupId] = (title, secondary)
            groupOrder.append(groupId)
        }

        for repo in sortedRepos(repos, sortOrder: sortOrder) {
            for worktree in sortedWorktrees(repo.worktrees, sortOrder: sortOrder) {
                let worktreeLocations = sortedUniqueLocations(locationsByWorktreeId[worktree.id] ?? [])
                guard !worktreeLocations.isEmpty else {
                    appendGroupIfNeeded(inactiveGroupId, title: "Inactive")
                    entriesByGroupId[inactiveGroupId, default: []].append(
                        PlacementEntry(repo: repo, worktree: worktree, location: nil)
                    )
                    continue
                }

                for location in worktreeLocations {
                    switch mode {
                    case .repo:
                        continue
                    case .pane:
                        let groupId = "pane:\(location.paneId.uuidString)"
                        if paneModeSeenWorktreesByGroup[groupId, default: []].contains(worktree.id) {
                            continue
                        }
                        paneModeSeenWorktreesByGroup[groupId, default: []].insert(worktree.id)
                        let paneOrdinal = paneOrdinalById[location.paneId] ?? 1
                        let tabOrdinal = tabOrdinalById[location.tabId] ?? location.tabIndex + 1
                        appendGroupIfNeeded(groupId, title: "Pane \(paneOrdinal)", secondary: "Tab \(tabOrdinal)")
                        entriesByGroupId[groupId, default: []].append(
                            PlacementEntry(repo: repo, worktree: worktree, location: location)
                        )
                    case .tab:
                        let groupId = "tab:\(location.tabId.uuidString)"
                        let tabOrdinal = tabOrdinalById[location.tabId] ?? location.tabIndex + 1
                        appendGroupIfNeeded(groupId, title: "Tab \(tabOrdinal)")
                        entriesByGroupId[groupId, default: []].append(
                            PlacementEntry(repo: repo, worktree: worktree, location: location)
                        )
                    }
                }
            }
        }

        let activeGroupIds = groupOrder.filter { $0 != inactiveGroupId }
        let orderedGroupIds =
            activeGroupIds + (entriesByGroupId[inactiveGroupId, default: []].isEmpty ? [] : [inactiveGroupId])

        var projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:]
        let groups: [RepoPresentationGroup] = orderedGroupIds.compactMap { groupId in
            guard let label = groupLabelsById[groupId], let entries = entriesByGroupId[groupId], !entries.isEmpty else {
                return nil
            }
            projectedRowsByGroupId[groupId] = projectedWorktreeRows(from: entries, groupId: groupId)
            return RepoPresentationGroup(
                id: groupId,
                repoTitle: label.title,
                organizationName: label.secondary,
                repos: repoItems(from: entries)
            )
        }
        return (groups, projectedRowsByGroupId)
    }

    private static func repoItems(from entries: [PlacementEntry]) -> [RepoPresentationItem] {
        var reposById: [UUID: RepoPresentationItem] = [:]
        var repoOrder: [UUID] = []
        for entry in entries {
            if reposById[entry.repo.id] == nil {
                var repo = entry.repo
                repo.worktrees = []
                reposById[entry.repo.id] = repo
                repoOrder.append(entry.repo.id)
            }
            reposById[entry.repo.id]?.worktrees.append(entry.worktree)
        }

        return repoOrder.compactMap { reposById[$0] }
    }

    private static func worktreeRowsByGroupId(
        from groups: [RepoPresentationGroup]
    ) -> [String: [RepoExplorerProjectedWorktreeRow]] {
        Dictionary(
            uniqueKeysWithValues: groups.map { group in
                let rows = group.repos.flatMap { repo in
                    repo.worktrees.map { worktree in
                        RepoExplorerProjectedWorktreeRow(
                            groupId: group.id,
                            repo: repo,
                            worktree: worktree,
                            rowId: rowId(
                                groupId: group.id,
                                repoId: repo.id,
                                worktreeId: worktree.id,
                                location: nil
                            ),
                            placementContext: nil
                        )
                    }
                }
                return (group.id, rows)
            })
    }

    private static func projectedWorktreeRows(
        from entries: [PlacementEntry],
        groupId: String
    ) -> [RepoExplorerProjectedWorktreeRow] {
        entries.map { entry in
            RepoExplorerProjectedWorktreeRow(
                groupId: groupId,
                repo: entry.repo,
                worktree: entry.worktree,
                rowId: rowId(
                    groupId: groupId,
                    repoId: entry.repo.id,
                    worktreeId: entry.worktree.id,
                    location: entry.location
                ),
                placementContext: entry.location.map {
                    RepoExplorerPlacementContext(
                        paneId: $0.paneId,
                        tabId: $0.tabId,
                        tabIndex: $0.tabIndex,
                        paneIndexInTab: $0.paneIndexInTab,
                        isActiveInTab: $0.isActiveInTab
                    )
                }
            )
        }
    }

    private static func rowId(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID,
        location: WorkspacePaneLocation?
    ) -> String {
        let placementToken = location.map { "pane:\($0.paneId.uuidString)" } ?? "inactive"
        return "worktree:\(groupId):\(repoId.uuidString):\(worktreeId.uuidString):\(placementToken)"
    }

    private static func sortedRepos(
        _ repos: [RepoPresentationItem],
        sortOrder: RepoExplorerSortOrder
    ) -> [RepoPresentationItem] {
        repos.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return compare(lhs.name, rhs.name, sortOrder: sortOrder)
        }
    }

    private static func sortedWorktrees(
        _ worktrees: [Worktree],
        sortOrder: RepoExplorerSortOrder
    ) -> [Worktree] {
        worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree
            }
            return compare(lhs.name, rhs.name, sortOrder: sortOrder)
        }
    }

    private static func compare(
        _ lhs: String,
        _ rhs: String,
        sortOrder: RepoExplorerSortOrder
    ) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        switch sortOrder {
        case .ascending:
            return comparison == .orderedAscending
        case .descending:
            return comparison == .orderedDescending
        }
    }

    private static func sortedUniqueLocations(_ locations: [WorkspacePaneLocation]) -> [WorkspacePaneLocation] {
        var seenPaneIds = Set<UUID>()
        return
            locations
            .sorted { lhs, rhs in
                if lhs.tabIndex != rhs.tabIndex {
                    return lhs.tabIndex < rhs.tabIndex
                }
                if lhs.paneIndexInTab != rhs.paneIndexInTab {
                    return lhs.paneIndexInTab < rhs.paneIndexInTab
                }
                return lhs.paneId.uuidString < rhs.paneId.uuidString
            }
            .filter { seenPaneIds.insert($0.paneId).inserted }
    }

    private static func sortedUniqueTabIds(_ locations: [WorkspacePaneLocation]) -> [UUID] {
        var seenTabIds = Set<UUID>()
        return
            locations
            .sorted {
                if $0.tabIndex != $1.tabIndex {
                    return $0.tabIndex < $1.tabIndex
                }
                return $0.tabId.uuidString < $1.tabId.uuidString
            }
            .compactMap { location in
                seenTabIds.insert(location.tabId).inserted ? location.tabId : nil
            }
    }
}
