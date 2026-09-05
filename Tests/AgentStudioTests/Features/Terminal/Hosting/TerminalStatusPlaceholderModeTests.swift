import AppKit
import Testing

@testable import AgentStudioTerminal

/// Verified empirically (not assumed) before writing these assertions:
/// `ProgressView()` bridges to a real `NSProgressIndicator` nested inside an
/// `AppKitPlatformViewHost` subview, discoverable by walking `.subviews`
/// after a real window lays the hierarchy out. `Text` and `Button` do not
/// produce a discoverable real `NSView` the same way, so "no retry or
/// dismiss control" is asserted through the `SurfaceErrorOverlayView`
/// container's own `isHidden` state instead — the container holding those
/// controls being hidden is the actual AppKit guarantee that they are
/// unreachable, regardless of how SwiftUI renders their content internally.
@MainActor
@Suite("Terminal status placeholder modes", .serialized)
struct TerminalStatusPlaceholderModeTests {
    @Test("waiting for geometry shows no progress indicator")
    func waitingForGeometryShowsNoProgressIndicator() {
        let (waitingWindow, waitingView) = mountedPlaceholder(mode: .waitingForGeometry)
        defer { waitingWindow.orderOut(nil) }
        #expect(findProgressIndicator(in: waitingView) == nil)

        // Sanity: the walker itself finds a real progress indicator for
        // `.preparing`, so the absence above is a genuine claim about
        // `.waitingForGeometry`, not a broken walk.
        let (preparingWindow, preparingView) = mountedPlaceholder(mode: .preparing)
        defer { preparingWindow.orderOut(nil) }
        #expect(findProgressIndicator(in: preparingView) != nil)
    }

    @Test("waiting for geometry exposes no retry or dismiss control")
    func waitingForGeometryExposesNoRetryOrDismissControl() throws {
        let (window, view) = mountedPlaceholder(mode: .waitingForGeometry)
        defer { window.orderOut(nil) }

        let errorOverlay = try #require(findErrorOverlay(in: view))
        #expect(errorOverlay.isHidden)
    }

    @Test("waiting for geometry does not request creation retry on bounds change")
    func waitingForGeometryDoesNotRequestCreationRetryOnBoundsChange() {
        let view = TerminalStatusPlaceholderView(paneId: UUID(), title: "Terminal", mode: .waitingForGeometry)
        #expect(view.shouldRetryCreationWhenBoundsChange == false)
    }

    @Test("failedToStart keeps sole ownership of retry and dismiss")
    func failedToStartKeepsSoleOwnershipOfRetryAndDismiss() throws {
        let (preparingWindow, preparingView) = mountedPlaceholder(mode: .preparing)
        defer { preparingWindow.orderOut(nil) }
        let (waitingWindow, waitingView) = mountedPlaceholder(mode: .waitingForGeometry)
        defer { waitingWindow.orderOut(nil) }
        let (failedWindow, failedView) = mountedPlaceholder(mode: .failedToStart)
        defer { failedWindow.orderOut(nil) }

        let preparingErrorOverlay = try #require(findErrorOverlay(in: preparingView))
        let waitingErrorOverlay = try #require(findErrorOverlay(in: waitingView))
        let failedErrorOverlay = try #require(findErrorOverlay(in: failedView))

        // Assert: only `.failedToStart` ever shows the retry/dismiss
        // container — `.preparing` and `.waitingForGeometry` both keep it
        // hidden, so neither can expose those controls.
        #expect(preparingErrorOverlay.isHidden)
        #expect(waitingErrorOverlay.isHidden)
        #expect(!failedErrorOverlay.isHidden)
    }
}

@MainActor
private func mountedPlaceholder(
    mode: TerminalStatusPlaceholderMode
) -> (window: NSWindow, view: TerminalStatusPlaceholderView) {
    let view = TerminalStatusPlaceholderView(paneId: UUID(), title: "Terminal", mode: mode)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    view.layoutSubtreeIfNeeded()
    return (window, view)
}

@MainActor
private func findProgressIndicator(in root: NSView) -> NSProgressIndicator? {
    if let progressIndicator = root as? NSProgressIndicator {
        return progressIndicator
    }
    for subview in root.subviews {
        if let match = findProgressIndicator(in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
private func findErrorOverlay(in root: NSView) -> SurfaceErrorOverlayView? {
    if let errorOverlay = root as? SurfaceErrorOverlayView {
        return errorOverlay
    }
    for subview in root.subviews {
        if let match = findErrorOverlay(in: subview) {
            return match
        }
    }
    return nil
}
