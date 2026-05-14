import Foundation

// swiftlint:disable discouraged_none_name
enum InboxNotificationGrouping: String, Sendable, Codable, Equatable, CaseIterable {
    case none
    case byRepo
    case byPane
    case byTab
}
// swiftlint:enable discouraged_none_name

enum InboxNotificationSort: String, Sendable, Codable, Equatable, CaseIterable {
    case newestFirst
    case oldestFirst
}
