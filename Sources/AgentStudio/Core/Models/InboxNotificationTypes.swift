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
}
// swiftlint:enable discouraged_none_name

enum InboxNotificationSort: String, Sendable, Codable, Equatable, CaseIterable {
    case newestFirst
    case oldestFirst
}
