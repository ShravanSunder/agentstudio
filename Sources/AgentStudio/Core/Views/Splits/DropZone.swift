import SwiftUI

/// Drop zone for horizontal split pane creation.
/// The entire view is a drop target; the split side is determined by
/// which half of the pane the cursor is in.
enum DropZone: String, Equatable, CaseIterable {
    case left
    case right

    /// Determines which drop zone the cursor is in based on horizontal position.
    static func calculate(at point: CGPoint, in size: CGSize) -> Self {
        guard size.width > 0 else { return .right }
        let relX = point.x / size.width
        return relX < 0.5 ? .left : .right
    }

    /// Convert to SplitTree.NewDirection for insertion.
    var newDirection: PaneSplitTree.NewDirection {
        switch self {
        case .left: return .left
        case .right: return .right
        }
    }

    /// Creates the overlay shape for visual feedback.
    /// Shows the full half of the pane where the new split will appear.
    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)
        let inset: CGFloat = 4

        switch self {
        case .left:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayColor)
                    .padding(inset)
                    .frame(width: geometry.size.width * 0.5)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayColor)
                    .padding(inset)
                    .frame(width: geometry.size.width * 0.5)
            }
        }
    }
}
