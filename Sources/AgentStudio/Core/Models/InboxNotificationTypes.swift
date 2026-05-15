import Foundation

// swiftlint:disable discouraged_none_name
enum InboxNotificationGrouping: String, Sendable, Codable, Equatable, CaseIterable {
    case byTab
    case byRepo
    case byPane
    case none
}
// swiftlint:enable discouraged_none_name

enum InboxNotificationSort: String, Sendable, Codable, Equatable, CaseIterable {
    case newestFirst
    case oldestFirst
}
