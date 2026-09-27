import AgentStudioCore
import Foundation

/// Panes has one fixed activity organization; Repos keeps its existing policy.
extension RepoExplorerProjection {
    static func organizedPanesByActivity(
        _ input: RepoExplorerOrganizationInput
    ) -> RepoExplorerOrganizedContent {
        let repositoriesByID = Dictionary(uniqueKeysWithValues: input.eligibleRepositories.map { ($0.id, $0) })
        let associated = input.eligibleRepositories.flatMap { repository in
            repository.worktrees.flatMap { worktree in
                input.destinationsByWorktreeId[worktree.id, default: []].map {
                    RepoExplorerProjectedPaneDestination.associated($0)
                }
            }
        }
        var seenPaneIDs: Set<UUID> = []
        let destinations = (associated + input.unassociatedDestinations.map { .unassociated($0) })
            .filter { seenPaneIDs.insert($0.paneId).inserted }
            .filter { input.snapshot.showsDrawerPanes || input.paneFacts[$0.paneId]?.isDrawerPane != true }
        let activityByPaneID = Dictionary(
            uniqueKeysWithValues: destinations.map { ($0.paneId, activity(for: $0, input: input)) }
        )
        var organized = RepoExplorerOrganizedContent()

        for sectionKind in [RepoExplorerSidebarSectionKind.pinnedPanes, .panes] {
            let sectionDestinations = destinations.filter { destination in
                let isPinned = input.snapshot.showsPinned && input.paneFacts[destination.paneId]?.isPinned == true
                return isPinned == (sectionKind == .pinnedPanes)
            }
            guard !sectionDestinations.isEmpty else { continue }

            let bucketTitles: [(key: String, title: String)] =
                if sectionKind == .pinnedPanes {
                    RepoExplorerPinnedActivityBucket.allCases.map { (String($0.rawValue), $0.title) }
                } else {
                    RepoExplorerActivityBucket.allCases.map { (String($0.rawValue), $0.title) }
                }
            var groups: [RepoPresentationGroup] = []
            for bucket in bucketTitles {
                let members = sectionDestinations.filter { destination in
                    guard let activity = activityByPaneID[destination.paneId] else { return false }
                    return sectionKind == .pinnedPanes
                        ? String(activity.pinnedBucket.rawValue) == bucket.key
                        : String(activity.unpinnedBucket.rawValue) == bucket.key
                }
                guard !members.isEmpty else { continue }
                let sortedMembers = members.sorted { lhs, rhs in
                    activityPrecedes(lhs, rhs, facts: input.paneFacts)
                }
                let arrangement = arrangeDrawerMembers(sortedMembers, facts: input.paneFacts)
                let groupID = "panes:\(sectionKind.rawValue):activity:\(bucket.key)"
                let repositoryIDs = Set(arrangement.members.compactMap(\.repoId))
                groups.append(
                    RepoPresentationGroup(
                        id: groupID,
                        repoTitle: bucket.title,
                        organizationName: nil,
                        repos: input.eligibleRepositories.filter { repositoryIDs.contains($0.id) }
                    )
                )
                organized.paneRows[groupID] = arrangement.members.map { destination in
                    var row = paneRow(
                        destination,
                        groupID: groupID,
                        repositoriesByID: repositoriesByID,
                        facts: input.paneFacts[destination.paneId],
                        branchFacts: input.branchFacts
                    )
                    row.drawerRail = arrangement.railByPaneID[destination.paneId] ?? .none
                    return row
                }
            }
            organized.sections.append(.init(kind: sectionKind, resolvedGroups: groups, loadingRepos: []))
        }
        return organized
    }

    private static func activity(
        for destination: RepoExplorerProjectedPaneDestination,
        input: RepoExplorerOrganizationInput
    ) -> RepoExplorerPaneActivityProjection {
        let time = input.paneFacts[destination.paneId]?.paneActivityTime
        return RepoExplorerPaneActivityProjection.make(
            time: input.snapshot.referenceInstant == nil ? nil : time,
            referenceInstant: input.snapshot.referenceInstant ?? time?.orderingInstant ?? ContinuousClock.now,
            wallNow: input.snapshot.referenceDate,
            calendar: input.snapshot.calendar
        )
    }

    private static func activityPrecedes(
        _ lhs: RepoExplorerProjectedPaneDestination,
        _ rhs: RepoExplorerProjectedPaneDestination,
        facts: [UUID: RepoExplorerPaneRowFacts]
    ) -> Bool {
        let left = facts[lhs.paneId]?.paneActivityTime?.orderingInstant
        let right = facts[rhs.paneId]?.paneActivityTime?.orderingInstant
        if left != right {
            if let left, let right { return left > right }
            return left != nil
        }
        return lhs.paneId.uuidString < rhs.paneId.uuidString
    }

    private static func arrangeDrawerMembers(
        _ sortedMembers: [RepoExplorerProjectedPaneDestination],
        facts: [UUID: RepoExplorerPaneRowFacts]
    ) -> (
        members: [RepoExplorerProjectedPaneDestination],
        railByPaneID: [UUID: RepoExplorerDrawerRail]
    ) {
        let memberIDs = Set(sortedMembers.map(\.paneId))
        let attachedDrawers = sortedMembers.filter { destination in
            guard let fact = facts[destination.paneId], fact.isDrawerPane,
                let ownerID = fact.drawerOwnerPaneID
            else { return false }
            return memberIDs.contains(ownerID)
        }
        var drawersByOwnerID: [UUID: [RepoExplorerProjectedPaneDestination]] = [:]
        for drawer in attachedDrawers {
            guard let ownerID = facts[drawer.paneId]?.drawerOwnerPaneID else { continue }
            drawersByOwnerID[ownerID, default: []].append(drawer)
        }
        let attachedIDs = Set(attachedDrawers.map(\.paneId))
        var arranged: [RepoExplorerProjectedPaneDestination] = []
        var rails: [UUID: RepoExplorerDrawerRail] = [:]
        arranged.reserveCapacity(sortedMembers.count)
        for destination in sortedMembers where !attachedIDs.contains(destination.paneId) {
            arranged.append(destination)
            let drawers = drawersByOwnerID[destination.paneId, default: []]
            guard !drawers.isEmpty else { continue }
            rails[destination.paneId] = .ownerWithDrawers
            for (index, drawer) in drawers.enumerated() {
                arranged.append(drawer)
                rails[drawer.paneId] = .drawer(isLast: index == drawers.count - 1)
            }
        }
        return (arranged, rails)
    }

    private static func paneRow(
        _ destination: RepoExplorerProjectedPaneDestination,
        groupID: String,
        repositoriesByID: [UUID: RepoPresentationItem],
        facts: RepoExplorerPaneRowFacts?,
        branchFacts: RepoExplorerPaneBranchProjectionFacts
    ) -> RepoExplorerProjectedPaneRow {
        let rowID = "pane-row:\(groupID):\(destination.paneId.uuidString)"
        let title = panePrimaryText(destination, terminalTitle: facts?.sidebarTerminalTitle, showsPaneNumber: false)
        let row: RepoExplorerProjectedPaneRow
        switch destination {
        case .associated(let associated):
            let branchText = normalizedBranchName(branchFacts.namesByWorktreeId[associated.worktreeId])
                .map { branchName in
                    let repositoryName = repositoriesByID[associated.repoId]?.name ?? "Repository"
                    return "\(repositoryName) · \(branchName)"
                }
            row = RepoExplorerProjectedPaneRow(
                groupId: groupID,
                repoId: associated.repoId,
                destination: associated,
                membershipOwner: .tab,
                rowId: rowID,
                primaryText: title,
                secondaryLine: facts?.secondaryLine,
                branchContextText: branchText,
                branchStatus: branchFacts.statusesByWorktreeId[associated.worktreeId],
                recencyText: facts?.recencyText ?? "—",
                recencyTier: facts?.recencyTier ?? .grey,
                isActive: facts?.isActive ?? false,
                isDrawerPane: facts?.isDrawerPane ?? false
            )
        case .unassociated(let unassociated):
            row = RepoExplorerProjectedPaneRow(
                groupId: groupID,
                destination: unassociated,
                rowId: rowID,
                primaryText: title,
                secondaryLine: facts?.secondaryLine,
                recencyText: facts?.recencyText ?? "—",
                recencyTier: facts?.recencyTier ?? .grey,
                isActive: facts?.isActive ?? false,
                isDrawerPane: facts?.isDrawerPane ?? false
            )
        }
        var pinnedRow = row
        pinnedRow.isPinned = facts?.isPinned ?? false
        pinnedRow.drawerOwnerPaneID = facts?.drawerOwnerPaneID
        let note: String? =
            if case .note(let text)? = facts?.secondaryLine { text } else { nil }
        pinnedRow.variants = RepoExplorerPaneRowVariants.make(
            title: title,
            branchContext: row.branchContextText,
            note: note,
            isDrawer: row.isDrawerPane,
            branchStatus: row.branchStatus,
            isActive: row.isActive
        )
        return pinnedRow
    }
}
