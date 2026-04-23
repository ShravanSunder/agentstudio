import SwiftUI

/// Renders a single split drop target overlay in tab-container coordinates.
struct PaneDropTargetOverlay: View {
    let target: PaneDropTarget?
    let targetRects: [PaneDropTarget: CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target,
                let targetRect = targetRects[target]
            {
                let markerRect = markerRect(for: target.zone, in: targetRect)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: targetRect.width, height: targetRect.height)
                    .offset(x: targetRect.minX, y: targetRect.minY)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: markerRect.width, height: markerRect.height)
                    .offset(x: markerRect.minX, y: markerRect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func markerRect(for zone: DropZoneSide, in targetRect: CGRect) -> CGRect {
        let markerWidth = min(AppStyles.General.Layout.dropTargetMarkerWidth, targetRect.width)
        let x =
            switch zone {
            case .left: targetRect.minX
            case .right: targetRect.maxX - markerWidth
            }
        return CGRect(x: x, y: targetRect.minY, width: markerWidth, height: targetRect.height)
    }
}
