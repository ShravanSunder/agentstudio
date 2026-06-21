import Foundation

// swiftlint:disable discouraged_none_name
enum InboxNotificationGrouping: String, Sendable, Codable, Equatable, CaseIterable {
    case byTab
    case byRepo
    case byPane
    case none

    var icon: CommandIcon {
        switch self {
        case .none:
            return .system(.line3Horizontal)
        case .byRepo:
            return .system(.folder)
        case .byPane:
            return .system(.rectangleSplit2x1)
        case .byTab:
            return .system(.rectangleStack)
        }
    }

    var commandLabel: String {
        switch self {
        case .none:
            return "None"
        case .byRepo:
            return "Repo"
        case .byPane:
            return "Pane"
        case .byTab:
            return "Tab"
        }
    }

    var commandHelpTarget: String {
        switch self {
        case .none:
            return "a flat list"
        case .byRepo:
            return "repo"
        case .byPane:
            return "pane"
        case .byTab:
            return "tab"
        }
    }

    var performanceMetricValue: String {
        switch self {
        case .none:
            return "none"
        case .byRepo:
            return "repo"
        case .byPane:
            return "pane"
        case .byTab:
            return "tab"
        }
    }
}
// swiftlint:enable discouraged_none_name

enum InboxNotificationSort: String, Sendable, Codable, Equatable, CaseIterable {
    case newestFirst
    case oldestFirst
}
