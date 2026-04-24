import Foundation

struct SidebarGroupKey: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

struct SidebarCheckoutColorKey: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

struct InboxNotificationGroupKey: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}
