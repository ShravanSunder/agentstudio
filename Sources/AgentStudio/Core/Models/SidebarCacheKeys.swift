import Foundation

/// Shared raw-string wrapper for durable sidebar cache keys.
///
/// Tags keep repo groups and inbox groups from crossing at compile time while
/// both persist as plain strings.
struct SidebarCacheKey<Tag>: Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension SidebarCacheKey: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension SidebarCacheKey: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

enum SidebarGroupKeyTag {}
enum InboxNotificationGroupKeyTag {}

typealias SidebarGroupKey = SidebarCacheKey<SidebarGroupKeyTag>
typealias InboxNotificationGroupKey = SidebarCacheKey<InboxNotificationGroupKeyTag>
