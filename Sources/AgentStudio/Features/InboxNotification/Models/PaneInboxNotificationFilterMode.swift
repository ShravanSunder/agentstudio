enum PaneInboxNotificationFilterMode: String, Sendable, Equatable, CaseIterable {
    case unread
    case all

    var label: String {
        switch self {
        case .unread:
            "Unread"
        case .all:
            "All"
        }
    }

    var systemImageName: String {
        switch self {
        case .unread:
            "line.3.horizontal.decrease.circle"
        case .all:
            "line.3.horizontal.circle"
        }
    }

    var toggled: Self {
        switch self {
        case .unread:
            .all
        case .all:
            .unread
        }
    }

    var helpText: String {
        switch self {
        case .unread:
            "Showing unread pane inbox messages"
        case .all:
            "Showing all pane inbox messages"
        }
    }
}
