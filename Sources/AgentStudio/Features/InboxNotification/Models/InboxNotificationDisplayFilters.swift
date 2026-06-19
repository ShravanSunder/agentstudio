enum InboxNotificationContentMode: String, Sendable, Codable, Equatable, CaseIterable {
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

enum InboxNotificationRowStateFilter: String, Sendable, Codable, Equatable, CaseIterable {
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

struct InboxNotificationDisplayOverride: Sendable, Equatable {
    let contentMode: InboxNotificationContentMode
    let rowStateFilter: InboxNotificationRowStateFilter
}
