import Foundation

enum InboxNotificationListNavigationDirection {
    case next
    case previous
}

enum InboxNotificationListEndpoint {
    case first
    case last
}

struct InboxNotificationListSection: Identifiable, Equatable {
    let id: String
    let label: String?
    let notifications: [InboxNotification]
    let isCollapsed: Bool

    var unreadCount: Int {
        notifications.reduce(0) { count, notification in
            notification.isRead ? count : count + 1
        }
    }

    var visibleNotifications: [InboxNotification] {
        isCollapsed ? [] : notifications
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
        return notifications.filter { notification in
            switch filter {
            case .worktree(let id):
                return notification.worktreeId == id
            case .repo(let id):
                return notification.repoId == id
            }
        }
    }

    private static func filterNotifications(
        _ notifications: [InboxNotification],
        searchText: String
    ) -> [InboxNotification] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return notifications }

        return notifications.filter { notification in
            notification.title.lowercased().contains(trimmedQuery)
                || (notification.body ?? "").lowercased().contains(trimmedQuery)
                || (notification.repoName ?? "").lowercased().contains(trimmedQuery)
                || (notification.worktreeName ?? "").lowercased().contains(trimmedQuery)
                || (notification.branchName ?? "").lowercased().contains(trimmedQuery)
        }
    }

    private static func buildSections(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) -> [InboxNotificationListSection] {
        switch grouping {
        case .none:
            return [
                InboxNotificationListSection(
                    id: "all",
                    label: nil,
                    notifications: notifications,
                    isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey("all"))
                )
            ]
        case .byRepo:
            return buildGroupedSections(
                notifications: notifications,
                key: { $0.repoName ?? "(no repo)" },
                label: { $0.repoName ?? "Unknown Repo" },
                collapsedGroups: collapsedGroups
            )
        case .byPane:
            return buildGroupedSections(
                notifications: notifications,
                key: { $0.paneId?.uuidString ?? "(no pane)" },
                label: { $0.worktreeName ?? $0.branchName ?? "Unknown Pane" },
                collapsedGroups: collapsedGroups
            )
        case .byTab:
            return buildGroupedSections(
                notifications: notifications,
                key: { $0.tabId?.uuidString ?? "(no tab)" },
                label: { notification in
                    guard let tabId = notification.tabId else { return "Unknown Tab" }
                    return "Tab \(tabId.uuidString.prefix(8))"
                },
                collapsedGroups: collapsedGroups
            )
        }
    }

    private static func buildGroupedSections(
        notifications: [InboxNotification],
        key: (InboxNotification) -> String,
        label: (InboxNotification) -> String,
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) -> [InboxNotificationListSection] {
        let buckets = Dictionary(grouping: notifications, by: key)
        return buckets.map { groupKey, notifications in
            let firstNotification = notifications[0]
            return InboxNotificationListSection(
                id: groupKey,
                label: label(firstNotification),
                notifications: notifications,
                isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey(groupKey))
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
}
