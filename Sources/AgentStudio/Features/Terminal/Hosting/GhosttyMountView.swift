import AppKit
import GhosttyKit

@MainActor
final class GhosttyMountView: NSView {
    private(set) var mountedView: NSView?

    func mount(_ view: NSView) {
        unmountCurrentView()

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        mountedView = view
    }

    func unmountCurrentView() {
        mountedView?.removeFromSuperview()
        mountedView = nil
    }

    // MARK: - Testing

    func mountAnyViewForTesting(_ view: NSView) {
        unmountCurrentView()
        for subview in subviews {
            subview.removeFromSuperview()
        }
        mount(view)
    }
}
