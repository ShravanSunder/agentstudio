import CoreGraphics
import Foundation

package struct DrawerCaptureGeometry: Equatable {
    package let panelFrameInTab: CGRect
    package let paneFramesInDrawer: [UUID: CGRect]

    package var containerBounds: CGRect {
        CGRect(origin: .zero, size: panelFrameInTab.size)
    }

    /// The drawer capture mounts as soon as the panel frame exists.
    ///
    /// Pane frames may briefly disagree with the panel during layout passes;
    /// the resolver handles out-of-range locations by returning a nil target.
    /// Refusing to mount on coordinate drift would silence drag entirely with
    /// no recovery path — the AppKit destination must exist for the session
    /// to dispatch into.
    package static func make(
        panelFrameInTab: CGRect,
        paneFramesInDrawer: [UUID: CGRect]
    ) -> Self? {
        guard !panelFrameInTab.isEmpty else { return nil }

        return Self(
            panelFrameInTab: panelFrameInTab,
            paneFramesInDrawer: paneFramesInDrawer
        )
    }

    package func locationInDrawer(fromTabLocation location: CGPoint) -> CGPoint {
        CGPoint(
            x: location.x - panelFrameInTab.minX,
            y: location.y - panelFrameInTab.minY
        )
    }
}
