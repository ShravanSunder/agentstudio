import AppKit
import SwiftUI

// MARK: - CommandBarPanel

/// NSPanel subclass that hosts the command bar UI.
/// Floating child window with vibrancy backdrop, positioned above terminal content.
final class CommandBarPanel: NSPanel {

    /// The hosting view containing SwiftUI command bar content.
    private var hostingView: NSHostingView<AnyView>?

    /// Called when the panel wants to dismiss (e.g., Escape key).
    /// Set by the controller so dismissal always goes through the proper lifecycle.
    var onDismiss: (() -> Void)?

    /// Visual effect backdrop for macOS blur.
    private let effectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        configure()
    }

    private func configure() {
        // Panel appearance
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Panel behavior
        hidesOnDeactivate = false
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = false

        // Shadow
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowBlurRadius = 20
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)

        // Content setup: effectView fills the panel
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        contentView = container
    }

    /// Set the SwiftUI content view.
    func setContent<V: View>(_ view: V) {
        hostingView?.removeFromSuperview()

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        hostingView = hosting
    }

    /// Position the panel centered horizontally, 20% down vertically, relative to the parent window.
    func positionRelativeTo(parentWindow: NSWindow) {
        let parentFrame = parentWindow.frame
        let contentFrame = parentWindow.contentLayoutRect

        let panelWidth = min(600, contentFrame.width)
        let panelX = parentFrame.origin.x + (parentFrame.width - panelWidth) / 2

        // 20% down from top of content area
        let contentTop = parentFrame.origin.y + contentFrame.origin.y + contentFrame.height
        let panelY = contentTop - contentFrame.height * 0.2 - frame.height

        var newFrame = frame
        newFrame.size.width = panelWidth
        newFrame.origin = NSPoint(x: panelX, y: panelY)
        setFrame(newFrame, display: true)
    }

    /// Size the panel to fill available space below the 20% vertical offset.
    /// Uses 60% of content height, but never extends past the window bottom.
    func updateHeight(parentWindow: NSWindow) {
        let contentFrame = parentWindow.contentLayoutRect
        let offsetFraction: CGFloat = 0.2
        let remainingBelow = contentFrame.height * (1 - offsetFraction)
        let panelHeight = min(contentFrame.height * 0.6, remainingBelow)

        var frame = self.frame
        let heightDelta = panelHeight - frame.height
        frame.size.height = panelHeight
        frame.origin.y -= heightDelta  // Grow downward
        setFrame(frame, display: true)
    }

    // MARK: - Key Handling

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Escape key — route through controller so backdrop + state are cleaned up
        onDismiss?()
    }
}
