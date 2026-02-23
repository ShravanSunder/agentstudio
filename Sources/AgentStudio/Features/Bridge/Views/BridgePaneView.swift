import AppKit
import SwiftUI
@preconcurrency import WebKit

/// Bridge pane embedding a BridgePaneController's WebPage via SwiftUI WebView.
///
/// Ownership: BridgePaneView (NSView/PaneView) holds a strong reference to
/// `BridgePaneController` (@Observable @MainActor). An `NSHostingView` wraps
/// the SwiftUI `BridgePaneContentView` which observes the controller.
/// Controller lifetime is tied to this NSView's lifetime in the AppKit layout hierarchy.
///
/// Follows the same pattern as `WebviewPaneView`.
final class BridgePaneView: PaneView {
    let controller: BridgePaneController
    private var hostingView: NSHostingView<BridgePaneContentView>?

    init(paneId: UUID, controller: BridgePaneController) {
        self.controller = controller
        super.init(paneId: paneId)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Content Interaction

    /// Suppresses web content interaction during management mode:
    /// - CSS `pointer-events: none` blocks hover (:hover, cursor, tooltips)
    /// - Capture-phase drag event listeners block drag UI that WKWebView
    ///   dispatches via its native NSView drag pathway, bypassing CSS pointer-events.
    override func setContentInteractionEnabled(_ enabled: Bool) {
        let js =
            enabled
            ? """
            document.documentElement.style.pointerEvents = 'auto';
            (function() {
                var b = window.__asDragBlock;
                if (b) {
                    document.removeEventListener('dragenter', b, true);
                    document.removeEventListener('dragover', b, true);
                    document.removeEventListener('dragleave', b, true);
                    document.removeEventListener('drop', b, true);
                    delete window.__asDragBlock;
                }
            })();
            """
            : """
            document.documentElement.style.pointerEvents = 'none';
            (function() {
                function b(e) { e.preventDefault(); e.stopPropagation(); }
                document.addEventListener('dragenter', b, true);
                document.addEventListener('dragover', b, true);
                document.addEventListener('dragleave', b, true);
                document.addEventListener('drop', b, true);
                window.__asDragBlock = b;
            })();
            """
        Task { @MainActor [weak self] in
            _ = try? await self?.controller.page.callJavaScript(js)
        }
    }

    // MARK: - Setup

    private func setupHostingView() {
        let contentView = BridgePaneContentView(controller: controller)
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
