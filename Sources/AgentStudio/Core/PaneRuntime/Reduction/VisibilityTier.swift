import Foundation

enum VisibilityTier: Int, Comparable, Sendable {
    case p0Visible = 0
    case p1Hidden = 1

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

protocol VisibilityTierResolver: Sendable {
    @MainActor func tier(for paneId: PaneId) -> VisibilityTier
}
