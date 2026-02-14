import SwiftUI

/// Drop zone for split pane creation.
/// Uses triangular proximity detection (Ghostty pattern) - the entire view is a drop target,
/// and the split direction is determined by which edge the cursor is closest to.
enum DropZone: String, Equatable, CaseIterable {
    case top
    case bottom
    case left
    case right

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side.
    static func calculate(at point: CGPoint, in size: CGSize) -> DropZone {
        guard size.width > 0, size.height > 0 else { return .right }

        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    /// The split direction this drop zone would create.
    var splitDirection: SplitViewDirection {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// Convert to SplitTree.NewDirection for insertion.
    var newDirection: PaneSplitTree.NewDirection {
        switch self {
        case .left: return .left
        case .right: return .right
        case .top: return .up
        case .bottom: return .down
        }
    }

    /// Creates the overlay shape for visual feedback.
    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)

        switch self {
        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
            }
        case .left:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
            }
        }
    }
}
