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

struct InboxNotificationListSectionHeader: Equatable {
    enum SourceKind: Equatable {
        case repo(organizationName: String?)
        case pane
        case tab
        case workspace
        case otherSources
    }

    enum Style: Equatable {
        case sourceGroup
    }

    let title: String
    let secondaryTitle: String?
    let sourceKind: SourceKind
    let accentColorHex: String?

    var label: String? {
        title
    }

    var style: Style {
        .sourceGroup
    }
}

struct InboxNotificationRepoGroupPresentation: Equatable {
    let groupId: String?
    let title: String
    let organizationName: String?
    let accentColorHex: String?

    init(
        groupId: String? = nil,
        title: String,
        organizationName: String?,
        accentColorHex: String?
    ) {
        self.groupId = groupId
        self.title = title
        self.organizationName = organizationName
        self.accentColorHex = accentColorHex
    }
}

private enum InboxNotificationSectionKey: Hashable {
    case ungrouped
    case repoGroup(id: String)
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
        case .repoGroup(let id):
            "repoGroup:\(id)"
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

private struct InboxNotificationListItem {
    let notification: InboxNotification
    let sourceDisplay: InboxNotificationSourceDisplay
    let normalizedSearchText: String

    init(notification: InboxNotification) {
        self.notification = notification
        let sourceDisplay = InboxNotificationSourceDisplay(notification: notification)
        self.sourceDisplay = sourceDisplay
        self.normalizedSearchText = sourceDisplay.searchText.lowercased()
    }
}

struct InboxNotificationListModel: Equatable {
    let sections: [InboxNotificationListSection]

    init(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        sort: InboxNotificationSort,
        searchText: String,
        unreadOnly: Bool = false,
        filter: InboxFilter? = nil,
        collapsedGroups: Set<InboxNotificationGroupKey> = [],
        repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation? = { _ in nil }
    ) {
        let sortedNotifications = Self.sortNotifications(notifications, sort: sort)
        let filteredNotifications = Self.filterNotifications(
            sortedNotifications,
            unreadOnly: unreadOnly,
            filter: filter
        )
        let sourceItems = filteredNotifications.map(InboxNotificationListItem.init)
        let textFilteredItems = Self.filterItems(
            sourceItems,
            searchText: searchText
        )
        self.sections = Self.buildSections(
            items: textFilteredItems,
            grouping: grouping,
            collapsedGroups: collapsedGroups,
            repoPresentation: repoPresentation
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
        unreadOnly: Bool,
        filter: InboxFilter?
    ) -> [InboxNotification] {
        notifications.filter { notification in
            if unreadOnly, notification.isRead { return false }
            guard let filter else { return true }
            return filter.matches(worktreeId: notification.worktreeId, repoId: notification.repoId)
        }
    }

    private static func filterItems(
        _ items: [InboxNotificationListItem],
        searchText: String
    ) -> [InboxNotificationListItem] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return items }

        return items.filter { item in
            item.normalizedSearchText.contains(trimmedQuery)
        }
    }

    private static func buildSections(
        items: [InboxNotificationListItem],
        grouping: InboxNotificationGrouping,
        collapsedGroups: Set<InboxNotificationGroupKey>,
        repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation?
    ) -> [InboxNotificationListSection] {
        switch grouping {
        case .none:
            let ungroupedKey = InboxNotificationSectionKey.ungrouped.id
            return [
                InboxNotificationListSection(
                    id: ungroupedKey,
                    header: nil,
                    notifications: items.map(\.notification),
                    isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey(ungroupedKey))
                )
            ]
        case .byRepo:
            return buildGroupedSections(
                items: items,
                key: { item in
                    let notification = item.notification
                    if let repoId = notification.repoId {
                        if let groupId = repoPresentation(repoId)?.groupId {
                            return .repoGroup(id: groupId)
                        }
                        return .repo(id: repoId)
                    }
                    if let repoName = notification.repoName { return .repoName(repoName) }
                    return .noRepo
                },
                header: { groupKey, items in
                    let resolvedRepoPresentation = repoPresentation(items.first?.notification.repoId)
                    switch groupKey {
                    case .repoName(let name):
                        return InboxNotificationListSectionHeader.sourceGroup(
                            title: name,
                            secondaryTitle: nil,
                            sourceKind: .repo(organizationName: nil),
                            accentColorHex: resolvedRepoPresentation?.accentColorHex
                        )
                    case .noRepo:
                        return InboxNotificationListSectionHeader.sourceGroup(
                            title: "Other sources",
                            secondaryTitle: nil,
                            sourceKind: .otherSources,
                            accentColorHex: nil
                        )
                    default:
                        return InboxNotificationListSectionHeader.sourceGroup(
                            title: resolvedRepoPresentation?.title
                                ?? bestGroupLabel(
                                    for: items,
                                    grouping: .byRepo,
                                    placeholder: "Other sources"
                                ),
                            secondaryTitle: resolvedRepoPresentation?.organizationName,
                            sourceKind: .repo(
                                organizationName: resolvedRepoPresentation?.organizationName
                            ),
                            accentColorHex: resolvedRepoPresentation?.accentColorHex
                        )
                    }
                },
                collapsedGroups: collapsedGroups
            )
        case .byPane:
            return buildGroupedSections(
                items: items,
                key: { item in
                    paneGroupingKey(for: item.notification)
                },
                header: { _, items in
                    let headerText = bestGroupHeaderText(for: items, grouping: .byPane, placeholder: "Other panes")
                    return .sourceGroup(
                        title: headerText.primary,
                        secondaryTitle: headerText.secondary,
                        sourceKind: .pane,
                        accentColorHex: nil
                    )
                },
                collapsedGroups: collapsedGroups
            )
        case .byTab:
            return buildGroupedSections(
                items: items,
                key: { item in
                    let notification = item.notification
                    guard let tabId = notification.tabId else { return .noTab }
                    return .tab(id: tabId)
                },
                header: { _, items in
                    let headerText = bestGroupHeaderText(for: items, grouping: .byTab, placeholder: "Untitled Tab")
                    return .sourceGroup(
                        title: headerText.primary,
                        secondaryTitle: headerText.secondary,
                        sourceKind: .tab,
                        accentColorHex: nil
                    )
                },
                collapsedGroups: collapsedGroups
            )
        }
    }

    private static func paneGroupingKey(for notification: InboxNotification) -> InboxNotificationSectionKey {
        guard case .pane(let source) = notification.source else { return .noPane }
        if source.paneRole == .drawerChild, let parentPaneId = source.parentPaneId {
            return .pane(id: parentPaneId)
        }
        return .pane(id: source.paneId)
    }

    private static func buildGroupedSections(
        items: [InboxNotificationListItem],
        key: (InboxNotificationListItem) -> InboxNotificationSectionKey,
        header: (InboxNotificationSectionKey, [InboxNotificationListItem]) -> InboxNotificationListSectionHeader,
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) -> [InboxNotificationListSection] {
        let buckets = Dictionary(grouping: items, by: key)
        return buckets.map { groupKey, items in
            let groupId = groupKey.id
            return InboxNotificationListSection(
                id: groupId,
                header: header(groupKey, items),
                notifications: items.map(\.notification),
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
        for items: [InboxNotificationListItem],
        grouping: InboxNotificationGrouping,
        placeholder: String
    ) -> String {
        bestGroupHeaderText(for: items, grouping: grouping, placeholder: placeholder).primary
    }

    private static func bestGroupHeaderText(
        for items: [InboxNotificationListItem],
        grouping: InboxNotificationGrouping,
        placeholder: String
    ) -> InboxNotificationSourceDisplay.GroupHeaderText {
        items
            .lazy
            .compactMap { item -> (timestamp: Date, text: InboxNotificationSourceDisplay.GroupHeaderText)? in
                guard
                    let text = item.sourceDisplay.groupHeaderText(for: grouping),
                    !text.primary.isEmpty,
                    text.primary != placeholder
                else {
                    return nil
                }
                return (timestamp: item.notification.timestamp, text: text)
            }
            .max { left, right in left.timestamp < right.timestamp }?
            .text ?? .init(primary: placeholder, secondary: nil)
    }
}

extension InboxNotificationListSectionHeader {
    static func sourceGroup(
        title: String,
        secondaryTitle: String?,
        sourceKind: SourceKind,
        accentColorHex: String? = nil
    ) -> Self {
        Self(
            title: title,
            secondaryTitle: secondaryTitle,
            sourceKind: sourceKind,
            accentColorHex: accentColorHex
        )
    }
}
