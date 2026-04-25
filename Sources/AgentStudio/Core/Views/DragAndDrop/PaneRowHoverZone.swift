import CoreGraphics
import Foundation

/// Horizontal hover zone within a pane in a row.
///
/// A pane is divided into three zones:
///
///     ┌──────┬─────────────────────┬──────┐
///     │ left │       center        │ right│
///     │ 1/4  │       1/2           │ 1/4  │
///     └──────┴─────────────────────┴──────┘
///
/// `.left` and `.right` are "between two panes" or "edge insert"
/// targets depending on whether the pane has a neighbor on that side.
/// `.center` is "split this pane" when the pane is splittable.
///
/// A `sideZoneFloor` ensures the side zones stay hittable on narrow
/// panes — when 1/4 of width is below the floor, the side zones grow
/// to the floor and the center zone shrinks (or disappears entirely
/// when the pane is too narrow to host all three zones).
enum PaneRowHoverZone: Equatable, Sendable {
    case left
    case center
    case right
}

extension CGRect {
    /// Resolves which hover zone the cursor's `x` coordinate falls
    /// into within this pane frame.
    func hoverZone(forX x: CGFloat, sideZoneFloor: CGFloat) -> PaneRowHoverZone {
        let naturalSideWidth = width / 4
        let sideWidth = max(naturalSideWidth, sideZoneFloor)

        // If two side zones can't both fit at the floor, split the
        // pane in half — no center zone, edges meet at midX.
        let centerStart: CGFloat
        let centerEnd: CGFloat
        if sideWidth * 2 >= width {
            centerStart = midX
            centerEnd = midX
        } else {
            centerStart = minX + sideWidth
            centerEnd = maxX - sideWidth
        }

        if x < centerStart { return .left }
        if x >= centerEnd { return .right }
        return .center
    }
}
