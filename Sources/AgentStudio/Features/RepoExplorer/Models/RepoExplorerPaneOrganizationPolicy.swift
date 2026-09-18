import AgentStudioCore
import Foundation

struct RepoExplorerPaneOrganizationMember: Equatable, Sendable {
    let paneID: UUID
    let repositoryID: UUID?
    let repositoryName: String?
    let tabID: UUID
    let tabOrder: Int
    let normalizedTitle: String
    let isPinned: Bool
    let activityAt: Date?
}

struct RepoExplorerPaneOrganizationPreferences: Equatable, Sendable {
    let groupingMode: RepoExplorerGroupingMode
    let subgroupMode: SidebarSubgroupMode
    let sortField: SidebarSortField
    let sortOrder: RepoExplorerSortOrder
    let referenceDate: Date
    let calendar: Calendar
}

struct RepoExplorerPaneOrganizationInput: Equatable, Sendable {
    let members: [RepoExplorerPaneOrganizationMember]
    let preferences: RepoExplorerPaneOrganizationPreferences
}

enum RepoExplorerPaneOrganizationGroupIdentity: Hashable, Sendable {
    case repository(id: UUID?, name: String)
    case tab(id: UUID, order: Int)
    case activity(RepoExplorerActivityBucket)
}

struct RepoExplorerPaneOrganizationGroup: Equatable, Sendable {
    let identity: RepoExplorerPaneOrganizationGroupIdentity
    let members: [RepoExplorerPaneOrganizationMember]
}

enum RepoExplorerPinnedPaneNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

enum RepoExplorerPaneOrganizationPolicy {
    static func orderedGroups(
        _ input: RepoExplorerPaneOrganizationInput
    ) -> [RepoExplorerPaneOrganizationGroup] {
        let preferences = input.preferences
        let grouped = Dictionary(grouping: input.members) { member in
            groupIdentity(for: member, preferences: preferences)
        }
        return grouped.keys.sorted(by: groupPrecedes).map { identity in
            let members = grouped[identity, default: []].sorted { lhs, rhs in
                if preferences.subgroupMode == .activity && preferences.groupingMode != .activity {
                    let leftBucket = activityBucket(for: lhs, preferences: preferences)
                    let rightBucket = activityBucket(for: rhs, preferences: preferences)
                    if leftBucket != rightBucket { return leftBucket.rawValue < rightBucket.rawValue }
                }
                return RepoExplorerLeafOrdering.precedes(
                    .init(name: lhs.normalizedTitle, activityAt: lhs.activityAt, identity: lhs.paneID),
                    .init(name: rhs.normalizedTitle, activityAt: rhs.activityAt, identity: rhs.paneID),
                    sortField: preferences.sortField,
                    sortOrder: preferences.sortOrder,
                    referenceDate: preferences.referenceDate
                )
            }
            return RepoExplorerPaneOrganizationGroup(identity: identity, members: members)
        }
    }

    static func orderedPaneIDs(
        _ input: RepoExplorerPaneOrganizationInput
    ) -> [UUID] {
        orderedGroups(input).flatMap { group in group.members.map(\.paneID) }
    }

    private static func groupIdentity(
        for member: RepoExplorerPaneOrganizationMember,
        preferences: RepoExplorerPaneOrganizationPreferences
    ) -> RepoExplorerPaneOrganizationGroupIdentity {
        switch preferences.groupingMode {
        case .repo: .repository(id: member.repositoryID, name: member.repositoryName ?? "No Repository")
        case .tab: .tab(id: member.tabID, order: member.tabOrder)
        case .activity: .activity(activityBucket(for: member, preferences: preferences))
        }
    }

    private static func activityBucket(
        for member: RepoExplorerPaneOrganizationMember,
        preferences: RepoExplorerPaneOrganizationPreferences
    ) -> RepoExplorerActivityBucket {
        RepoExplorerActivityBucket.classify(
            activityAt: member.activityAt, now: preferences.referenceDate, calendar: preferences.calendar
        )
    }

    private static func groupPrecedes(
        _ lhs: RepoExplorerPaneOrganizationGroupIdentity,
        _ rhs: RepoExplorerPaneOrganizationGroupIdentity
    ) -> Bool {
        switch (lhs, rhs) {
        case (.repository(let leftID, let leftName), .repository(let rightID, let rightName)):
            let comparison = leftName.localizedCaseInsensitiveCompare(rightName)
            return comparison == .orderedSame
                ? (leftID?.uuidString ?? "unassociated") < (rightID?.uuidString ?? "unassociated")
                : comparison == .orderedAscending
        case (.tab(let leftID, let leftOrder), .tab(let rightID, let rightOrder)):
            return leftOrder == rightOrder ? leftID.uuidString < rightID.uuidString : leftOrder < rightOrder
        case (.activity(let leftBucket), .activity(let rightBucket)):
            return leftBucket.rawValue < rightBucket.rawValue
        default:
            preconditionFailure("One pane organization input must use one grouping mode")
        }
    }
}

enum RepoExplorerPinnedPaneNavigationPolicy {
    static func orderedPaneIDs(
        _ input: RepoExplorerPaneOrganizationInput
    ) -> [UUID] {
        RepoExplorerPaneOrganizationPolicy.orderedPaneIDs(
            RepoExplorerPaneOrganizationInput(
                members: input.members.filter(\.isPinned),
                preferences: input.preferences
            )
        )
    }

    static func targetPaneID(
        from originPaneID: UUID?,
        direction: RepoExplorerPinnedPaneNavigationDirection,
        orderedPaneIDs: [UUID]
    ) -> UUID? {
        guard !orderedPaneIDs.isEmpty else { return nil }
        guard let originPaneID, let originIndex = orderedPaneIDs.firstIndex(of: originPaneID) else {
            return direction == .next ? orderedPaneIDs.first : orderedPaneIDs.last
        }
        let delta = direction == .next ? 1 : -1
        return orderedPaneIDs[(originIndex + delta + orderedPaneIDs.count) % orderedPaneIDs.count]
    }
}
