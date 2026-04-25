import SwiftUI

/// Renders the active main-pane drop target.
///
/// Every visual has a soft-fill `region`. Slot/edge targets also
/// have an `insertionMarker` bar painted on top of the region —
/// see `DropTargetVisual` for the per-target-type breakdown.
struct PaneDropTargetOverlay: View {
    let visual: DropTargetVisual?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let visual {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: visual.region.width, height: visual.region.height)
                    .offset(x: visual.region.minX, y: visual.region.minY)

                if let marker = visual.insertionMarker {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: marker.width, height: marker.height)
                        .offset(x: marker.minX, y: marker.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
