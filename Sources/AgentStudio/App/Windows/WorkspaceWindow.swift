import AppKit

/// The workspace window's instance-bound ingress for AppKit ordering changes.
final class WorkspaceWindow: NSWindow {
    var didCompleteOrdering: (() -> Void)?

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWindowNumber: Int) {
        super.order(place, relativeTo: otherWindowNumber)
        didCompleteOrdering?()
    }
}
