import Foundation

enum InboxNotificationListNavigationDirection: Sendable {
    case next
    case previous
}

enum InboxNotificationListEndpoint: Sendable {
    case first
    case last
}

struct InboxNotificationListSection: Identifiable, Equatable, Sendable {
    let id: String
    let header: InboxNotificationListSectionHeader?
    let notifications: [InboxNotification]
    let isCollapsed: Bool

    var label: String? {
        header?.label
    }

    var unreadCount: Int {
        notifications.reduce(0) { count, notification in
            notification.contributesToRollUpAlert ? count + 1 : count
        }
    }

    var visibleNotifications: [InboxNotification] {
        isCollapsed ? [] : notifications
    }
}

extension Array where Element == InboxNotificationListSection {
    var visibleNotificationIds: [UUID] {
        flatMap(\.visibleNotifications).map(\.id)
    }
}

struct InboxNotificationListSectionHeader: Equatable, Sendable {
    enum SourceKind: Equatable, Sendable {
        case repo(organizationName: String?)
        case pane
        case tab
        case workspace
        case otherSources
    }

    enum Style: Equatable, Sendable {
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

struct InboxNotificationRepoGroupPresentation: Equatable, Sendable {
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

private enum InboxNotificationSectionKey: Hashable, Sendable {
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

private struct InboxNotificationListItem: Sendable {
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

struct InboxNotificationListModel: Equatable, Sendable {
    static let empty = Self(sections: [])

    let sections: [InboxNotificationListSection]

    init(sections: [InboxNotificationListSection]) {
        self.sections = sections
    }

    init(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        sort: InboxNotificationSort,
        searchText: String,
        unreadOnly: Bool = false,
        contentMode: InboxNotificationContentMode = .all,
        rowStateFilter: InboxNotificationRowStateFilter = .all,
        filter: InboxFilter? = nil,
        collapsedGroups: Set<InboxNotificationGroupKey> = [],
        repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation? = { _ in nil }
    ) {
        let effectiveRowStateFilter: InboxNotificationRowStateFilter = unreadOnly ? .unreadOnly : rowStateFilter
        let sortedNotifications = Self.sortNotifications(notifications, sort: sort)
        let filteredNotifications = Self.filterNotifications(
            sortedNotifications,
            contentMode: contentMode,
            rowStateFilter: effectiveRowStateFilter,
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

    init(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        sort: InboxNotificationSort,
        searchText: String,
        contentMode: InboxNotificationContentMode,
        rowStateFilter: InboxNotificationRowStateFilter,
        filter: InboxFilter?,
        collapsedGroups: Set<InboxNotificationGroupKey>,
        repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation?,
        cancellationCheck: () throws -> Void
    ) throws {
        try cancellationCheck()
        let sortedNotifications = try Self.sortNotifications(
            notifications,
            sort: sort,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()
        let filteredNotifications = try Self.filterNotifications(
            sortedNotifications,
            contentMode: contentMode,
            rowStateFilter: rowStateFilter,
            filter: filter,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()
        let sourceItems = try filteredNotifications.enumerated().map { index, notification in
            if index.isMultiple(of: 256) {
                try cancellationCheck()
            }
            return InboxNotificationListItem(notification: notification)
        }
        try cancellationCheck()
        let textFilteredItems = try Self.filterItems(
            sourceItems,
            searchText: searchText,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()
        self.sections = try Self.buildSections(
            items: textFilteredItems,
            grouping: grouping,
            collapsedGroups: collapsedGroups,
            repoPresentation: repoPresentation,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()
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

    private static func sortNotifications(
        _ notifications: [InboxNotification],
        sort: InboxNotificationSort,
        cancellationCheck: () throws -> Void
    ) throws -> [InboxNotification] {
        let orderedBefore: (InboxNotification, InboxNotification) -> Bool =
            sort == .newestFirst
            ? { $0.timestamp > $1.timestamp }
            : { $0.timestamp < $1.timestamp }
        return try cancellableMergeSort(
            notifications,
            orderedBefore: orderedBefore,
            cancellationCheck: cancellationCheck
        )
    }

    private static func cancellableMergeSort(
        _ notifications: [InboxNotification],
        orderedBefore: (InboxNotification, InboxNotification) -> Bool,
        cancellationCheck: () throws -> Void
    ) throws -> [InboxNotification] {
        guard notifications.count > 1 else { return notifications }
        var source = notifications
        var destination = notifications
        var width = 1
        var comparisonCount = 0

        while width < notifications.count {
            var lowerBound = 0
            while lowerBound < notifications.count {
                let middle = min(lowerBound + width, notifications.count)
                let upperBound = min(lowerBound + (width * 2), notifications.count)
                var leftIndex = lowerBound
                var rightIndex = middle
                var destinationIndex = lowerBound

                while leftIndex < middle || rightIndex < upperBound {
                    comparisonCount += 1
                    if comparisonCount.isMultiple(of: 256) { try cancellationCheck() }
                    if rightIndex >= upperBound
                        || (leftIndex < middle && orderedBefore(source[leftIndex], source[rightIndex]))
                    {
                        destination[destinationIndex] = source[leftIndex]
                        leftIndex += 1
                    } else {
                        destination[destinationIndex] = source[rightIndex]
                        rightIndex += 1
                    }
                    destinationIndex += 1
                }
                lowerBound += width * 2
            }
            swap(&source, &destination)
            width *= 2
            try cancellationCheck()
        }
        return source
    }

    private static func filterNotifications(
        _ notifications: [InboxNotification],
        contentMode: InboxNotificationContentMode,
        rowStateFilter: InboxNotificationRowStateFilter,
        filter: InboxFilter?
    ) -> [InboxNotification] {
        notifications.filter { notification in
            guard contentMode.includes(notification) else { return false }
            guard rowStateFilter.includes(notification) else { return false }
            guard let filter else { return true }
            return filter.matches(worktreeId: notification.worktreeId, repoId: notification.repoId)
        }
    }

    private static func filterNotifications(
        _ notifications: [InboxNotification],
        contentMode: InboxNotificationContentMode,
        rowStateFilter: InboxNotificationRowStateFilter,
        filter: InboxFilter?,
        cancellationCheck: () throws -> Void
    ) throws -> [InboxNotification] {
        var filteredNotifications: [InboxNotification] = []
        filteredNotifications.reserveCapacity(notifications.count)
        for (index, notification) in notifications.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            guard contentMode.includes(notification) else { continue }
            guard rowStateFilter.includes(notification) else { continue }
            guard filter?.matches(worktreeId: notification.worktreeId, repoId: notification.repoId) ?? true else {
                continue
            }
            filteredNotifications.append(notification)
        }
        return filteredNotifications
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

    private static func filterItems(
        _ items: [InboxNotificationListItem],
        searchText: String,
        cancellationCheck: () throws -> Void
    ) throws -> [InboxNotificationListItem] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return items }

        var filteredItems: [InboxNotificationListItem] = []
        filteredItems.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            if item.normalizedSearchText.contains(trimmedQuery) {
                filteredItems.append(item)
            }
        }
        return filteredItems
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

    private static func buildSections(
        items: [InboxNotificationListItem],
        grouping: InboxNotificationGrouping,
        collapsedGroups: Set<InboxNotificationGroupKey>,
        repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation?,
        cancellationCheck: () throws -> Void
    ) throws -> [InboxNotificationListSection] {
        try cancellationCheck()
        switch grouping {
        case .none:
            var notifications: [InboxNotification] = []
            notifications.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 256) { try cancellationCheck() }
                notifications.append(item.notification)
            }
            let groupId = InboxNotificationSectionKey.ungrouped.id
            return [
                InboxNotificationListSection(
                    id: groupId,
                    header: nil,
                    notifications: notifications,
                    isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey(groupId))
                )
            ]
        case .byRepo:
            return try buildGroupedSections(
                items: items,
                key: { item in
                    let notification = item.notification
                    if let repoId = notification.repoId {
                        if let groupId = repoPresentation(repoId)?.groupId { return .repoGroup(id: groupId) }
                        return .repo(id: repoId)
                    }
                    if let repoName = notification.repoName { return .repoName(repoName) }
                    return .noRepo
                },
                header: { groupKey, groupedItems in
                    let presentation = repoPresentation(groupedItems.first?.notification.repoId)
                    switch groupKey {
                    case .repoName(let name):
                        return .sourceGroup(
                            title: name, secondaryTitle: nil, sourceKind: .repo(organizationName: nil),
                            accentColorHex: presentation?.accentColorHex)
                    case .noRepo:
                        return .sourceGroup(
                            title: "Other sources", secondaryTitle: nil, sourceKind: .otherSources)
                    default:
                        return .sourceGroup(
                            title: presentation?.title
                                ?? bestGroupLabel(for: groupedItems, grouping: .byRepo, placeholder: "Other sources"),
                            secondaryTitle: presentation?.organizationName,
                            sourceKind: .repo(organizationName: presentation?.organizationName),
                            accentColorHex: presentation?.accentColorHex)
                    }
                },
                collapsedGroups: collapsedGroups,
                cancellationCheck: cancellationCheck
            )
        case .byPane:
            return try buildGroupedSections(
                items: items,
                key: { paneGroupingKey(for: $0.notification) },
                header: { _, groupedItems in
                    let text = bestGroupHeaderText(
                        for: groupedItems, grouping: .byPane, placeholder: "Other panes")
                    return .sourceGroup(
                        title: text.primary, secondaryTitle: text.secondary, sourceKind: .pane)
                },
                collapsedGroups: collapsedGroups,
                cancellationCheck: cancellationCheck
            )
        case .byTab:
            return try buildGroupedSections(
                items: items,
                key: { item in
                    guard let tabId = item.notification.tabId else { return .noTab }
                    return .tab(id: tabId)
                },
                header: { _, groupedItems in
                    let text = bestGroupHeaderText(
                        for: groupedItems, grouping: .byTab, placeholder: "Untitled Tab")
                    return .sourceGroup(
                        title: text.primary, secondaryTitle: text.secondary, sourceKind: .tab)
                },
                collapsedGroups: collapsedGroups,
                cancellationCheck: cancellationCheck
            )
        }
    }

    private static func buildGroupedSections(
        items: [InboxNotificationListItem],
        key: (InboxNotificationListItem) -> InboxNotificationSectionKey,
        header: (InboxNotificationSectionKey, [InboxNotificationListItem]) -> InboxNotificationListSectionHeader,
        collapsedGroups: Set<InboxNotificationGroupKey>,
        cancellationCheck: () throws -> Void
    ) throws -> [InboxNotificationListSection] {
        var buckets: [InboxNotificationSectionKey: [InboxNotificationListItem]] = [:]
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            buckets[key(item), default: []].append(item)
        }

        var sections: [InboxNotificationListSection] = []
        sections.reserveCapacity(buckets.count)
        for (index, bucket) in buckets.enumerated() {
            if index.isMultiple(of: 64) { try cancellationCheck() }
            let groupId = bucket.key.id
            sections.append(
                InboxNotificationListSection(
                    id: groupId,
                    header: header(bucket.key, bucket.value),
                    notifications: bucket.value.map(\.notification),
                    isCollapsed: collapsedGroups.contains(InboxNotificationGroupKey(groupId))
                ))
        }
        try cancellationCheck()
        return sections.sorted { left, right in
            let ordering = (left.label ?? "").localizedCaseInsensitiveCompare(right.label ?? "")
            return ordering == .orderedSame ? left.id < right.id : ordering == .orderedAscending
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
