import Foundation

enum VisibilityTier: Int, Comparable, Sendable {
    case p0ActivePane = 0
    case p1ActiveDrawer = 1
    case p2VisibleActiveTab = 2
    case p3Background = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static var p0Visible: Self { .p0ActivePane }
    static var p1Hidden: Self { .p3Background }
}

protocol VisibilityTierResolver: Sendable {
    @MainActor func tier(for paneId: PaneId) -> VisibilityTier
}
