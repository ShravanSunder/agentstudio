import AgentStudioCore
import Foundation

/// Runs inside the existing detached projection. Membership is established before
/// grouping; leaf sorting can therefore never move an item between sections.
struct RepoExplorerOrganizedContent {
    var sections: [RepoExplorerSidebarSection] = []
    var worktreeRows: [String: [RepoExplorerProjectedWorktreeRow]] = [:]
    var paneRows: [String: [RepoExplorerProjectedPaneRow]] = [:]
}

struct RepoExplorerOrganizationInput {
    let snapshot: RepoExplorerSnapshot
    let eligibleRepositories: [RepoPresentationItem]
    let loadingRepos: [RepoPresentationItem]
    let metadataByRepoId: [UUID: RepoIdentityMetadata]
    let checkoutColors: [UUID: String]
    let destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]]
    let destinationsByRepoId: [UUID: [RepoExplorerPaneDestination]]
    let unassociatedDestinations: [RepoExplorerUnassociatedPaneDestination]
    let paneFacts: [UUID: RepoExplorerPaneRowFacts]
    let tabFacts: [UUID: RepoExplorerTabGroupFacts]
    let branchFacts: RepoExplorerPaneBranchProjectionFacts
}

private struct RepoExplorerLeafSortKey {
    let name: String
    let activityAt: Date?
    let identity: UUID
}

extension RepoExplorerProjection {
    static func organizedContent(_ input: RepoExplorerOrganizationInput) -> RepoExplorerOrganizedContent {
        let snapshot = input.snapshot
        let eligibleRepositories = input.eligibleRepositories
        let paneFacts = input.paneFacts
        let tabFacts = input.tabFacts
        let branchFacts = input.branchFacts
        if snapshot.surface == .repos {
            return organizedRepositories(input)
        }
        let reposById = Dictionary(uniqueKeysWithValues: eligibleRepositories.map { ($0.id, $0) })
        let destinations = organizationPaneDestinations(input)
        var result = RepoExplorerOrganizedContent()
        for sectionKind in [RepoExplorerSidebarSectionKind.pinnedPanes, .panes] {
            let members = destinations.filter { destination in
                let isPinned = snapshot.showsPinned && paneFacts[destination.paneId]?.isPinned == true
                return isPinned == (sectionKind == .pinnedPanes)
            }
            guard !members.isEmpty else { continue }
            let grouped = Dictionary(grouping: members) { destination in
                switch snapshot.groupingMode {
                case .repo: destination.repoId?.uuidString ?? "unassociated"
                case .tab: destination.tabId.uuidString
                case .activity:
                    String(activityBucket(destination.paneId, snapshot: snapshot, facts: paneFacts).rawValue)
                }
            }
            let orderedKeys = grouped.keys.sorted { lhs, rhs in
                switch snapshot.groupingMode {
                case .repo:
                    let leftName = grouped[lhs]?.first?.repoId.flatMap { reposById[$0]?.name } ?? "No Repository"
                    let rightName = grouped[rhs]?.first?.repoId.flatMap { reposById[$0]?.name } ?? "No Repository"
                    let comparison = leftName.localizedCaseInsensitiveCompare(rightName)
                    return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
                case .tab:
                    let leftIndex = grouped[lhs]?.first?.tabIndex ?? .max
                    let rightIndex = grouped[rhs]?.first?.tabIndex ?? .max
                    return leftIndex == rightIndex ? lhs < rhs : leftIndex < rightIndex
                case .activity: return (Int(lhs) ?? .max) < (Int(rhs) ?? .max)
                }
            }
            var groups: [RepoPresentationGroup] = []
            for key in orderedKeys {
                guard let members = grouped[key], let first = members.first else { continue }
                let groupId = "panes:\(sectionKind.rawValue):\(snapshot.groupingMode.rawValue):\(key)"
                let title: String
                switch snapshot.groupingMode {
                case .repo: title = first.repoId.flatMap { reposById[$0]?.name } ?? "No Repository"
                case .tab: title = tabFacts[first.tabId]?.displayTitle ?? "Tab \(first.tabIndex + 1)"
                case .activity: title = activityBucket(first.paneId, snapshot: snapshot, facts: paneFacts).title
                }
                let memberRepoIds = Set(members.compactMap(\.repoId))
                groups.append(
                    RepoPresentationGroup(
                        id: groupId, repoTitle: title, organizationName: nil,
                        repos: eligibleRepositories.filter { memberRepoIds.contains($0.id) }
                    ))
                let sortNamesByPaneId = Dictionary(
                    uniqueKeysWithValues: members.map { destination in
                        let title =
                            paneFacts[destination.paneId]?.sidebarTerminalTitle
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return (destination.paneId, title.isEmpty ? "zsh" : title)
                    })
                var rows = members.map { destination in
                    var row = tabPaneRow(
                        groupId: groupId, destination: destination, reposById: reposById,
                        paneFacts: paneFacts[destination.paneId], branchFacts: branchFacts
                    )
                    row.isPinned = paneFacts[destination.paneId]?.isPinned ?? false
                    if snapshot.subgroupMode == .activity && snapshot.groupingMode != .activity {
                        row.activitySubgroup = activityBucket(destination.paneId, snapshot: snapshot, facts: paneFacts)
                    }
                    return row
                }
                rows.sort { lhs, rhs in
                    if lhs.activitySubgroup != rhs.activitySubgroup {
                        return (lhs.activitySubgroup?.rawValue ?? 0) < (rhs.activitySubgroup?.rawValue ?? 0)
                    }
                    return leafPrecedes(
                        .init(
                            name: sortNamesByPaneId[lhs.destination.paneId] ?? "",
                            activityAt: paneFacts[lhs.destination.paneId]?.activityAt,
                            identity: lhs.destination.paneId),
                        .init(
                            name: sortNamesByPaneId[rhs.destination.paneId] ?? "",
                            activityAt: paneFacts[rhs.destination.paneId]?.activityAt,
                            identity: rhs.destination.paneId),
                        snapshot: snapshot
                    )
                }
                result.paneRows[groupId] = rows
            }
            result.sections.append(.init(kind: sectionKind, resolvedGroups: groups, loadingRepos: []))
        }
        return result
    }

    private static func organizationPaneDestinations(
        _ input: RepoExplorerOrganizationInput
    ) -> [RepoExplorerProjectedPaneDestination] {
        let associated = input.eligibleRepositories.flatMap { repo in
            repo.worktrees.flatMap { worktree in
                input.destinationsByWorktreeId[worktree.id, default: []].map {
                    RepoExplorerProjectedPaneDestination.associated($0)
                }
            }
        }
        return associated + input.unassociatedDestinations.map { .unassociated($0) }
    }

    private static func organizedRepositories(_ input: RepoExplorerOrganizationInput) -> RepoExplorerOrganizedContent {
        let snapshot = input.snapshot
        let eligibleRepositories = input.eligibleRepositories
        let loadingRepos = input.loadingRepos
        let metadataByRepoId = input.metadataByRepoId
        let checkoutColors = input.checkoutColors
        let destinationsByWorktreeId = input.destinationsByWorktreeId
        let destinationsByRepoId = input.destinationsByRepoId
        let paneFacts = input.paneFacts
        func section(for repo: RepoPresentationItem) -> RepoExplorerSidebarSectionKind {
            if snapshot.showsPinned && repo.isPinned { return .pinnedRepositories }
            return destinationsByRepoId[repo.id, default: []].isEmpty ? .repositories : .openRepositories
        }
        let activityByWorktreeId = destinationsByWorktreeId.compactMapValues { destinations in
            destinations.compactMap { validActivity(paneFacts[$0.paneId]?.activityAt, snapshot: snapshot) }.max()
        }
        var result = RepoExplorerOrganizedContent()
        for kind in [RepoExplorerSidebarSectionKind.pinnedRepositories, .openRepositories, .repositories] {
            let members = eligibleRepositories.filter { section(for: $0) == kind }
            let loading = loadingRepos.filter { section(for: $0) == kind }
            guard !members.isEmpty || !loading.isEmpty else { continue }
            let groups = remoteIdentityGroups(repos: members, metadataByRepoId: metadataByRepoId, sortOrder: .ascending)
                .map { group in
                    RepoPresentationGroup(
                        id: "repos:\(kind.rawValue):\(group.id)", repoTitle: group.repoTitle,
                        organizationName: group.organizationName, repos: group.repos
                    )
                }
            let rowsByGroup = worktreeRowsByGroupId(from: groups, checkoutColorHexByRepoId: checkoutColors)
            for (groupId, unsortedRows) in rowsByGroup {
                var rows = unsortedRows.map { original in
                    var row = original
                    if snapshot.subgroupMode == .activity {
                        row.activitySubgroup = RepoExplorerActivityBucket.classify(
                            activityAt: activityByWorktreeId[row.worktree.id],
                            now: snapshot.referenceDate, calendar: snapshot.calendar
                        )
                    }
                    return row
                }
                rows.sort { lhs, rhs in
                    if lhs.activitySubgroup != rhs.activitySubgroup {
                        return (lhs.activitySubgroup?.rawValue ?? 0) < (rhs.activitySubgroup?.rawValue ?? 0)
                    }
                    return leafPrecedes(
                        .init(
                            name: lhs.worktree.name, activityAt: activityByWorktreeId[lhs.worktree.id],
                            identity: lhs.worktree.id),
                        .init(
                            name: rhs.worktree.name, activityAt: activityByWorktreeId[rhs.worktree.id],
                            identity: rhs.worktree.id),
                        snapshot: snapshot
                    )
                }
                result.worktreeRows[groupId] = rows
            }
            result.sections.append(.init(kind: kind, resolvedGroups: groups, loadingRepos: loading))
        }
        return result
    }

    private static func activityBucket(
        _ paneId: UUID, snapshot: RepoExplorerSnapshot, facts: [UUID: RepoExplorerPaneRowFacts]
    ) -> RepoExplorerActivityBucket {
        RepoExplorerActivityBucket.classify(
            activityAt: facts[paneId]?.activityAt, now: snapshot.referenceDate, calendar: snapshot.calendar
        )
    }

    private static func validActivity(_ date: Date?, snapshot: RepoExplorerSnapshot) -> Date? {
        guard let date, date.timeIntervalSince1970.isFinite,
            snapshot.referenceDate.timeIntervalSince1970.isFinite, date <= snapshot.referenceDate
        else { return nil }
        return date
    }

    private static func leafPrecedes(
        _ lhs: RepoExplorerLeafSortKey, _ rhs: RepoExplorerLeafSortKey, snapshot: RepoExplorerSnapshot
    ) -> Bool {
        if snapshot.sortField == .activity {
            let left = validActivity(lhs.activityAt, snapshot: snapshot)
            let right = validActivity(rhs.activityAt, snapshot: snapshot)
            // Unknown evidence is always last, including descending order.
            if (left == nil) != (right == nil) { return left != nil }
            if let left, let right, left != right {
                return snapshot.sortOrder == .ascending ? left < right : left > right
            }
        }
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == (snapshot.sortOrder == .ascending ? .orderedAscending : .orderedDescending)
        }
        return lhs.identity.uuidString < rhs.identity.uuidString
    }
}
