import CoreGraphics
import Foundation

/// Visual representation of a drag drop target.
///
/// Both main and drawer overlays render through this type so the look
/// stays consistent across contexts. Every visual has a soft-fill
/// `region` and may optionally have a bright `insertionMarker` bar
/// painted on top.
///
///   ▸ split target            region = cursor's half of the pane
///                             marker = nil (no hard line on splits)
///
///   ▸ between two panes       region = the right 1/4 of the left
///                                      pane + the left 1/4 of the
///                                      right pane (the actual hover
///                                      zone the user is in)
///                             marker = thin bar at the boundary
///
///   ▸ edge insert             region = outer 1/4 of the edge pane
///                             marker = thin bar at the row edge
///
///   ▸ drawer new-row band     region = the band itself (top or
///                                      bottom 1/5 of the panel)
///                             marker = nil
struct DropTargetVisual: Equatable, Sendable {
    let region: CGRect
    let insertionMarker: CGRect?

    static func region(_ rect: CGRect) -> Self {
        Self(region: rect, insertionMarker: nil)
    }

    static func zoneWithMarker(zone: CGRect, marker: CGRect) -> Self {
        Self(region: zone, insertionMarker: marker)
    }
}
