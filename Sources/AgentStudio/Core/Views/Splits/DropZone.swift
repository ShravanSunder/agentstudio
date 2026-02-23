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
    /// Uses an edge insertion marker so the target reads as "between panes"
    /// instead of replacing the destination pane.
    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let markerColor = Color.accentColor.opacity(0.85)
        let previewColor = Color.accentColor.opacity(0.16)
        let inset: CGFloat = 4
        let availableWidth = max(geometry.size.width - (inset * 2), 1)
        let markerWidth = min(AppStyle.dropTargetMarkerWidth, availableWidth)
        let minimumPreviewWidth = max(
            AppStyle.dropTargetPreviewMinimumWidth,
            AppStyle.splitMinimumPaneSize + (AppStyle.paneGap * 2)
        )
        let fractionalPreviewWidth = geometry.size.width * AppStyle.dropTargetPreviewMaxFraction
        let unclampedPreviewWidth = max(minimumPreviewWidth, fractionalPreviewWidth)
        let previewWidth = min(unclampedPreviewWidth, availableWidth)

        switch self {
        case .left:
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(previewColor)
                        .frame(width: previewWidth)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(markerColor)
                        .frame(width: markerWidth)
                }
                .padding(inset)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(previewColor)
                        .frame(width: previewWidth)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(markerColor)
                        .frame(width: markerWidth)
                }
                .padding(inset)
            }
        }
    }
}
