import SwiftUI

/// Renders a single split drop target overlay in tab-container coordinates.
struct PaneDropTargetOverlay: View {
    let target: PaneDropTarget?
    let paneFrames: [UUID: CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target,
                let paneFrame = paneFrames[target.paneId]
            {
                let previewRect = target.zone.overlayRect(in: paneFrame)
                let markerRect = target.zone.markerRect(in: paneFrame)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: previewRect.width, height: previewRect.height)
                    .offset(x: previewRect.minX, y: previewRect.minY)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: markerRect.width, height: markerRect.height)
                    .offset(x: markerRect.minX, y: markerRect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
