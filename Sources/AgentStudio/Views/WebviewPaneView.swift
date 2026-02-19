import AppKit
import SwiftUI

/// Webview pane embedding a real browser via SwiftUI WebView/WebPage.
///
/// Ownership: WebviewPaneView (NSView/PaneView) holds a strong reference to
/// `WebviewPaneController` (@Observable @MainActor). An `NSHostingView` wraps
/// the SwiftUI `WebviewPaneContentView` which observes the controller.
/// Controller lifetime is tied to this NSView's lifetime in the AppKit layout hierarchy.
final class WebviewPaneView: PaneView {
    let controller: WebviewPaneController
    private var hostingView: NSHostingView<WebviewPaneContentView>?

    init(paneId: UUID, state: WebviewState) {
        self.controller = WebviewPaneController(paneId: paneId, state: state)
        super.init(paneId: paneId)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    /// Capture current tab state for persistence.
    func currentState() -> WebviewState {
        controller.snapshot()
    }

    // MARK: - Setup

    private func setupHostingView() {
        let contentView = WebviewPaneContentView(controller: controller)
        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        self.hostingView = hosting
    }
}
