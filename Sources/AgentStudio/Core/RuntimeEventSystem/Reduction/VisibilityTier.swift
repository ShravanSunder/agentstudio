import Foundation

package enum VisibilityTier: Int, Comparable, Sendable {
    case p0Visible = 0
    case p1Hidden = 1

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

package protocol VisibilityTierResolver: Sendable {
    @MainActor func tier(for paneId: PaneId) -> VisibilityTier
}
