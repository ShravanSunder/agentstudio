import AppKit
import GhosttyKit

@MainActor
final class GhosttyMountView: NSView {
    private(set) var mountedSurfaceView: Ghostty.SurfaceView?

    func mount(_ surfaceView: Ghostty.SurfaceView) {
        unmountCurrentSurface()

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        mountedSurfaceView = surfaceView
    }

    func unmountCurrentSurface() {
        mountedSurfaceView?.removeFromSuperview()
        mountedSurfaceView = nil
    }

    // MARK: - Testing

    func mountAnyViewForTesting(_ view: NSView) {
        unmountCurrentSurface()
        for subview in subviews {
            subview.removeFromSuperview()
        }

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
