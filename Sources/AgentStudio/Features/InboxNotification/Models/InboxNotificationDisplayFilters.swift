package enum InboxNotificationContentMode: String, Sendable, Codable, Equatable, CaseIterable {
    case rollUpAlerts
    case activity
    case all

    var label: String {
        switch self {
        case .rollUpAlerts:
            "Attention"
        case .activity:
            "Activity"
        case .all:
            "All"
        }
    }

    func includes(_ notification: InboxNotification) -> Bool {
        switch self {
        case .rollUpAlerts:
            notification.displayLane == .actionNeeded
                || notification.displayLane == .safety
                || notification.displayLane == .settledAgent
        case .activity:
            notification.displayLane == .activity
        case .all:
            true
        }
    }
}

package enum InboxNotificationRowStateFilter: String, Sendable, Codable, Equatable, CaseIterable {
    case unreadOnly
    case all

    var label: String {
        switch self {
        case .unreadOnly:
            "Unread"
        case .all:
            "All"
        }
    }

    func includes(_ notification: InboxNotification) -> Bool {
        switch self {
        case .unreadOnly:
            !notification.isRead
        case .all:
            true
        }
    }
}

package struct InboxNotificationDisplayOverride: Sendable, Equatable {
    package let contentMode: InboxNotificationContentMode
    package let rowStateFilter: InboxNotificationRowStateFilter

    package init(
        contentMode: InboxNotificationContentMode,
        rowStateFilter: InboxNotificationRowStateFilter
    ) {
        self.contentMode = contentMode
        self.rowStateFilter = rowStateFilter
    }
}
