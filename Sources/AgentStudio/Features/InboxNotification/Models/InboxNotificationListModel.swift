import Foundation

enum InboxNotificationListNavigationDirection {
    case next
    case previous
}

enum InboxNotificationListEndpoint {
    case first
    case last
}

struct InboxNotificationListSectionHeader: Equatable {
    enum Style: Equatable {
        case plain
        case repo(organizationName: String?)
    }

    let label: String?
    let style: Style
}

struct InboxNotificationListSection: Identifiable, Equatable {
    let id: String
    let header: InboxNotificationListSectionHeader?
    let notifications: [InboxNotification]
    let isCollapsed: Bool

    var label: String? {
        header?.label
    }

    var unreadCount: Int {
        notifications.reduce(0) { count, notification in
            notification.isRead ? count : count + 1
        }
    }

    var visibleNotifications: [InboxNotification] {
        isCollapsed ? [] : notifications
    }
}

private enum InboxNotificationSectionKey: Hashable {
    case ungrouped
    case repo(id: UUID)
    case repoName(String)
    case noRepo
    case pane(id: UUID)
    case noPane
    case tab(id: UUID)
    case noTab

    var id: String {
        switch self {
        case .ungrouped:
            "__ungrouped__"
        case .repo(let id):
            "repo:\(id.uuidString)"
        case .repoName(let name):
            name
        case .noRepo:
            "__no_repo__"
        case .pane(let id):
            id.uuidString
        case .noPane:
            "__no_pane__"
        case .tab(let id):
            id.uuidString
        case .noTab:
            "__no_tab__"
        }
    }
}

struct InboxNotificationListModel: Equatable {
    let sections: [InboxNotificationListSection]

    init(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        sort: InboxNotificationSort,
        searchText: String,
        filter: InboxFilter? = nil,
        collapsedGroups: Set<InboxNotificationGroupKey> = []
    ) {
        let sortedNotifications = Self.sortNotifications(notifications, sort: sort)
        let sourceFilteredNotifications = Self.filterNotifications(
            sortedNotifications,
            filter: filter
        )
        let textFilteredNotifications = Self.filterNotifications(
            sourceFilteredNotifications,
            searchText: searchText
        )
        self.sections = Self.buildSections(
            notifications: textFilteredNotifications,
            grouping: grouping,
            collapsedGroups: collapsedGroups
        )
    }

    func groupBoundaryTarget(
        from focusedNotificationId: UUID?,
        direction: InboxNotificationListNavigationDirection
    ) -> UUID? {
        guard let focusedNotificationId else { return nil }
        guard
            let currentSectionIndex = sections.firstIndex(where: { section in
                section.visibleNotifications.contains { $0.id == focusedNotificationId }
            })
        else {
            return nil
        }

        let step: Int
        switch direction {
        case .next:
            step = 1
        case .previous:
            step = -1
        }

        var targetSectionIndex = currentSectionIndex + step
        while sections.indices.contains(targetSectionIndex) {
            if let firstVisibleNotificationId = sections[targetSectionIndex].visibleNotifications.first?.id {
                return firstVisibleNotificationId
            }
            targetSectionIndex += step
        }
        return nil
    }

    func endpointTarget(_ endpoint: InboxNotificationListEndpoint) -> UUID? {
        let notifications = sections.flatMap(\.visibleNotifications)
        switch endpoint {
        case .first:
            return notifications.first?.id
        case .last:
            return notifications.last?.id
        }
    }

    private static func sortNotifications(
        _ notifications: [InboxNotification],
        sort: InboxNotificationSort
    ) -> [InboxNotification] {
        switch sort {
        case .newestFirst:
            return notifications.sorted { $0.timestamp > $1.timestamp }
        case .oldestFirst:
            return notifications.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private static func filterNotifications(
        _ notifications: [InboxNotification],
        filter: InboxFilter?
    ) -> [InboxNotification] {
        guard let filter else { return notifications }
        return notifications.filter {
            filter.matches(worktreeId: $0.worktreeId, repoId: $0.repoId)
        }
    }

    private static func filterNotifications(
        _ notifications: [InboxNotification],
        searchText: String
    ) -> [InboxNotification] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return notifications }

        return notifications.filter { notification in
            InboxNotificationSourceDisplay(notification: notification)
                .searchText
                .lowercased()
                .contains(trimmedQuery)
        }
    }

    private static func buildSections(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) -> [InboxNotificationListSection] {
        switch grouping {
        case .none:
            let ungroupedKey = InboxNotificationSectionKey.ungrouped.id
            return [
                InboxNotificationListSection(
                    id: ungroupedKey,
                    header: nil,
                    notifications: notifications,
                    isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey(ungroupedKey))
                )
            ]
        case .byRepo:
            return buildGroupedSections(
                notifications: notifications,
                key: { notification in
                    if let repoId = notification.repoId { return .repo(id: repoId) }
                    if let repoName = notification.repoName { return .repoName(repoName) }
                    return .noRepo
                },
                header: { key, notifications in
                    switch key {
                    case .repoName(let name):
                        return .repo(label: name, organizationName: nil)
                    case .noRepo:
                        return .plain(label: "Other sources")
                    default:
                        return .repo(
                            label: bestGroupLabel(
                                for: notifications,
                                grouping: .byRepo,
                                placeholder: "Other sources"
                            ),
                            organizationName: nil
                        )
                    }
                },
                collapsedGroups: collapsedGroups
            )
        case .byPane:
            return buildGroupedSections(
                notifications: notifications,
                key: { notification in
                    guard let paneId = notification.paneId else { return .noPane }
                    return .pane(id: paneId)
                },
                header: { _, notifications in
                    .plain(label: bestGroupLabel(for: notifications, grouping: .byPane, placeholder: "Other panes"))
                },
                collapsedGroups: collapsedGroups
            )
        case .byTab:
            return buildGroupedSections(
                notifications: notifications,
                key: { notification in
                    guard let tabId = notification.tabId else { return .noTab }
                    return .tab(id: tabId)
                },
                header: { _, notifications in
                    .plain(label: bestGroupLabel(for: notifications, grouping: .byTab, placeholder: "Untitled Tab"))
                },
                collapsedGroups: collapsedGroups
            )
        }
    }

    private static func buildGroupedSections(
        notifications: [InboxNotification],
        key: (InboxNotification) -> InboxNotificationSectionKey,
        header: (InboxNotificationSectionKey, [InboxNotification]) -> InboxNotificationListSectionHeader,
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) -> [InboxNotificationListSection] {
        let buckets = Dictionary(grouping: notifications, by: key)
        return buckets.map { groupKey, notifications in
            let groupId = groupKey.id
            return InboxNotificationListSection(
                id: groupId,
                header: header(groupKey, notifications),
                notifications: notifications,
                isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey(groupId))
            )
        }.sorted { left, right in
            let leftLabel = left.label ?? ""
            let rightLabel = right.label ?? ""
            let labelOrdering = leftLabel.localizedCaseInsensitiveCompare(rightLabel)
            if labelOrdering == .orderedSame {
                return left.id < right.id
            }
            return labelOrdering == .orderedAscending
        }
    }

    private static func bestGroupLabel(
        for notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        placeholder: String
    ) -> String {
        notifications
            .sorted { $0.timestamp > $1.timestamp }
            .lazy
            .map { InboxNotificationSourceDisplay.groupLabel(for: $0, grouping: grouping) }
            .first { !$0.isEmpty && $0 != placeholder } ?? placeholder
    }
}

extension InboxNotificationListSectionHeader {
    static func plain(label: String) -> Self {
        Self(label: label, style: .plain)
    }

    static func repo(label: String, organizationName: String?) -> Self {
        Self(label: label, style: .repo(organizationName: organizationName))
    }
}
