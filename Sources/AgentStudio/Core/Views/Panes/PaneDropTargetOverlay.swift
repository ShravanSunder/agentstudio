import SwiftUI

/// Renders the active main-pane drop target.
///
/// The visual model is shared with the drawer overlay
/// (see `DropTargetVisual`):
///
///   ▸ `.region(rect)` — soft fill, no border line. Used for splits;
///     the rect is the half of the pane the new pane will land in
///     (Option B), so the user sees which side wins.
///   ▸ `.insertionMarker(rect)` — bright vertical bar. Used for
///     between-pane inserts and edge inserts.
struct PaneDropTargetOverlay: View {
    let visual: DropTargetVisual?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let visual {
                switch visual {
                case .region(let rect):
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                case .insertionMarker(let rect):
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
