import AppKit
import SwiftUI

/// Webview pane embedding a real browser via SwiftUI WebView/WebPage.
///
/// Ownership: WebviewPaneMountView (NSView mounted under `PaneHostView`) holds a strong reference to
/// `WebviewPaneController` (@Observable @MainActor). An `NSHostingView` wraps
/// the SwiftUI `WebviewPaneContentView` which observes the controller.
/// Controller lifetime is tied to this NSView's lifetime in the AppKit layout hierarchy.
final class WebviewPaneMountView: NSView, PaneMountedContent {
    let paneId: UUID
    let controller: WebviewPaneController
    let runtime: WebviewRuntime
    private var hostingView: NSHostingView<WebviewPaneContentView>?

    init(paneId: UUID, state: WebviewState) {
        self.paneId = paneId
        let controller = WebviewPaneController(paneId: paneId, state: state)
        self.controller = controller
        self.runtime = controller.runtime
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncHostingViewFrame()
    }

    override func layout() {
        super.layout()
        syncHostingViewFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setContentInteractionEnabled(!ManagementModeMonitor.shared.isActive)
        syncHostingViewFrame()
    }

    /// Capture current tab state for persistence.
    func currentState() -> WebviewState {
        controller.snapshot()
    }

    // MARK: - Content Interaction

    /// Delegates management mode interaction suppression to the controller's
    /// persistent user-script pipeline (current document + future navigations).
    func setContentInteractionEnabled(_ enabled: Bool) {
        controller.setWebContentInteractionEnabled(enabled)
    }

    // MARK: - Setup

    private func setupHostingView() {
        let contentView = WebviewPaneContentView(controller: controller)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        self.hostingView = hosting
        syncHostingViewFrame()
    }

    private func syncHostingViewFrame() {
        guard let hostingView else { return }
        if hostingView.frame != bounds {
            hostingView.frame = bounds
        }
        hostingView.layoutSubtreeIfNeeded()
    }
}
