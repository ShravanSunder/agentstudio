import AppKit
import SwiftUI

/// Bridge pane embedding a BridgePaneController's WebPage via SwiftUI WebView.
///
/// Ownership: BridgePaneView (NSView/PaneView) holds a strong reference to
/// `BridgePaneController` and its `BridgeRuntime` (@Observable @MainActor). An `NSHostingView` wraps
/// the SwiftUI `BridgePaneContentView` which observes the controller.
/// Controller lifetime is tied to this NSView's lifetime in the AppKit layout hierarchy.
///
/// Follows the same pattern as `WebviewPaneView`.
final class BridgePaneView: PaneView {
    let controller: BridgePaneController
    let runtime: BridgeRuntime
    private var hostingView: NSHostingView<BridgePaneContentView>?

    init(paneId: UUID, controller: BridgePaneController) {
        self.controller = controller
        self.runtime = controller.runtime
        super.init(paneId: paneId)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Content Interaction

    /// Delegates management mode interaction suppression to the controller's
    /// persistent user-script pipeline (current document + future navigations).
    override func setContentInteractionEnabled(_ enabled: Bool) {
        controller.setWebContentInteractionEnabled(enabled)
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
