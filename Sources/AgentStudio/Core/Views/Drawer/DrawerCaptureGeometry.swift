import CoreGraphics
import Foundation

struct DrawerCaptureGeometry: Equatable {
    let panelFrameInTab: CGRect
    let paneFramesInDrawer: [UUID: CGRect]

    var containerBounds: CGRect {
        CGRect(origin: .zero, size: panelFrameInTab.size)
    }

    /// The drawer capture mounts as soon as the panel frame exists.
    ///
    /// Pane frames may briefly disagree with the panel during layout passes;
    /// the resolver handles out-of-range locations by returning a nil target.
    /// Refusing to mount on coordinate drift would silence drag entirely with
    /// no recovery path — the AppKit destination must exist for the session
    /// to dispatch into.
    static func make(
        panelFrameInTab: CGRect,
        paneFramesInDrawer: [UUID: CGRect]
    ) -> Self? {
        guard !panelFrameInTab.isEmpty else { return nil }

        return Self(
            panelFrameInTab: panelFrameInTab,
            paneFramesInDrawer: paneFramesInDrawer
        )
    }

    func locationInDrawer(fromTabLocation location: CGPoint) -> CGPoint {
        CGPoint(
            x: location.x - panelFrameInTab.minX,
            y: location.y - panelFrameInTab.minY
        )
    }
}
