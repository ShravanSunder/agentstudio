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
        let paneFrame = CGRect(origin: .zero, size: geometry.size)
        overlay(paneFrame: paneFrame)
    }

    /// Returns the translucent preview rectangle for a pane frame in container coordinates.
    func overlayRect(in paneFrame: CGRect) -> CGRect {
        let inset: CGFloat = 4
        let availableWidth = max(paneFrame.width - (inset * 2), 1)
        let minimumPreviewWidth = max(
            AppStyle.dropTargetPreviewMinimumWidth,
            AppStyle.splitMinimumPaneSize + (AppStyle.paneGap * 2)
        )
        let fractionalPreviewWidth = paneFrame.width * AppStyle.dropTargetPreviewMaxFraction
        let unclampedPreviewWidth = max(minimumPreviewWidth, fractionalPreviewWidth)
        let previewWidth = min(unclampedPreviewWidth, availableWidth)
        let height = max(paneFrame.height - (inset * 2), 1)
        let x =
            switch self {
            case .left: paneFrame.minX + inset
            case .right: paneFrame.maxX - inset - previewWidth
            }
        return CGRect(x: x, y: paneFrame.minY + inset, width: previewWidth, height: height)
    }

    /// Returns the solid insertion marker rectangle for a pane frame in container coordinates.
    func markerRect(in paneFrame: CGRect) -> CGRect {
        let previewRect = overlayRect(in: paneFrame)
        let markerWidth = min(AppStyle.dropTargetMarkerWidth, previewRect.width)
        let x =
            switch self {
            case .left: previewRect.minX
            case .right: previewRect.maxX - markerWidth
            }
        return CGRect(x: x, y: previewRect.minY, width: markerWidth, height: previewRect.height)
    }

    @ViewBuilder
    private func overlay(paneFrame: CGRect) -> some View {
        let markerColor = Color.accentColor.opacity(0.85)
        let previewColor = Color.accentColor.opacity(0.16)
        let previewRect = overlayRect(in: paneFrame)
        let markerRect = markerRect(in: paneFrame)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(previewColor)
                .frame(width: previewRect.width, height: previewRect.height)
                .offset(x: previewRect.minX, y: previewRect.minY)
            RoundedRectangle(cornerRadius: 4)
                .fill(markerColor)
                .frame(width: markerRect.width, height: markerRect.height)
                .offset(x: markerRect.minX, y: markerRect.minY)
        }
    }
}
