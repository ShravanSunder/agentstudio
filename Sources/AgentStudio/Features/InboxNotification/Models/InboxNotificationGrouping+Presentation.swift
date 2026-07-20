extension InboxNotificationGrouping {
    var icon: CommandIcon {
        switch self {
        case .none:
            .system(.line3Horizontal)
        case .byRepo:
            .system(.folder)
        case .byPane:
            .system(.rectangleSplit2x1)
        case .byTab:
            .system(.rectangleStack)
        }
    }

    var commandLabel: String {
        switch self {
        case .none:
            "None"
        case .byRepo:
            "Repo"
        case .byPane:
            "Pane"
        case .byTab:
            "Tab"
        }
    }

    var commandHelpTarget: String {
        switch self {
        case .none:
            "a flat list"
        case .byRepo:
            "repo"
        case .byPane:
            "pane"
        case .byTab:
            "tab"
        }
    }

    var performanceMetricValue: String {
        switch self {
        case .none:
            "none"
        case .byRepo:
            "repo"
        case .byPane:
            "pane"
        case .byTab:
            "tab"
        }
    }
}
