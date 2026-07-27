import Foundation

/// Shared raw-string wrapper for durable sidebar cache keys.
///
/// Tags keep repo groups and inbox groups from crossing at compile time while
/// both persist as plain strings.
package struct SidebarCacheKey<Tag>: Codable, Sendable, ExpressibleByStringLiteral {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    package init(stringLiteral value: String) {
        self.rawValue = value
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension SidebarCacheKey: Equatable {
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension SidebarCacheKey: Hashable {
    package func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

package enum SidebarGroupKeyTag {}
package enum InboxNotificationGroupKeyTag {}

package typealias SidebarGroupKey = SidebarCacheKey<SidebarGroupKeyTag>
package typealias InboxNotificationGroupKey = SidebarCacheKey<InboxNotificationGroupKeyTag>
