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

    var unreadCount: Int {
        notifications.reduce(0) { count, notification in
            notification.isRead ? count : count + 1
        }
    }
}

struct InboxNotificationListModel: Equatable {
    let sections: [InboxNotificationListSection]

    init(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        sort: InboxNotificationSort,
        searchText: String
    ) {
        let sortedNotifications = Self.sortNotifications(notifications, sort: sort)
        let filteredNotifications = Self.filterNotifications(
            sortedNotifications,
            searchText: searchText
        )
        self.sections = Self.buildSections(
            notifications: filteredNotifications,
            grouping: grouping
        )
    }

    func groupBoundaryTarget(
        from focusedNotificationId: UUID?,
        direction: InboxNotificationListNavigationDirection
    ) -> UUID? {
        guard let focusedNotificationId else { return nil }
        guard
            let currentSectionIndex = sections.firstIndex(where: { section in
                section.notifications.contains { $0.id == focusedNotificationId }
            })
        else {
            return nil
        }

        let targetSectionIndex: Int
        switch direction {
        case .next:
            targetSectionIndex = currentSectionIndex + 1
        case .previous:
            targetSectionIndex = currentSectionIndex - 1
        }

        guard sections.indices.contains(targetSectionIndex) else { return nil }
        return sections[targetSectionIndex].notifications.first?.id
    }

    func endpointTarget(_ endpoint: InboxNotificationListEndpoint) -> UUID? {
        let notifications = sections.flatMap(\.notifications)
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
        grouping: InboxNotificationGrouping
    ) -> [InboxNotificationListSection] {
        switch grouping {
        case .none:
            return [
                InboxNotificationListSection(
                    id: "all",
                    label: nil,
                    notifications: notifications
                )
            ]
        case .byRepo:
            return buildGroupedSections(
                notifications: notifications,
                key: { $0.repoName ?? "(no repo)" },
                label: { $0.repoName ?? "Unknown Repo" }
            )
        case .byPane:
            return buildGroupedSections(
                notifications: notifications,
                key: { $0.paneId?.uuidString ?? "(no pane)" },
                label: { $0.worktreeName ?? $0.branchName ?? "Unknown Pane" }
            )
        case .byTab:
            return buildGroupedSections(
                notifications: notifications,
                key: { $0.tabId?.uuidString ?? "(no tab)" },
                label: { notification in
                    guard let tabId = notification.tabId else { return "Unknown Tab" }
                    return "Tab \(tabId.uuidString.prefix(8))"
                }
            )
        }
    }

    private static func buildGroupedSections(
        notifications: [InboxNotification],
        key: (InboxNotification) -> String,
        label: (InboxNotification) -> String
    ) -> [InboxNotificationListSection] {
        let buckets = Dictionary(grouping: notifications, by: key)
        return buckets.map { groupKey, notifications in
            let firstNotification = notifications[0]
            return InboxNotificationListSection(
                id: groupKey,
                label: label(firstNotification),
                notifications: notifications
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
