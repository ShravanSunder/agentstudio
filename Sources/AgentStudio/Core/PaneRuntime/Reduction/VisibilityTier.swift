import Foundation

enum VisibilityTier: Int, Comparable, Sendable {
    case p0_activePane = 0
    case p1_activeDrawer = 1
    case p2_visibleActiveTab = 2
    case p3_background = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

protocol VisibilityTierResolver: Sendable {
    @MainActor func tier(for paneId: PaneId) -> VisibilityTier
}
