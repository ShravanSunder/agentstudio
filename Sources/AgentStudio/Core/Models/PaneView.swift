import AppKit

/// Container NSView that blocks all AppKit event routing to pane content
/// during management mode. When `hitTest` returns `nil`, the entire subtree
/// (terminal surfaces, WKWebView, etc.) becomes invisible to AppKit.
///
/// Kept as a belt-and-suspenders layer alongside `PaneView.hitTest`.
@MainActor
final class ManagementModeContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !ManagementModeMonitor.shared.isActive else { return nil }
        return super.hitTest(point)
    }
}

/// Base class for all pane views that can appear in the split tree.
/// Provides the common identity (paneId) and SwiftUI bridging contract.
///
/// ## Management mode interaction blocking (4 layers)
///
/// 1. **Clicks**: ``hitTest(_:)`` returns `nil` during management mode.
/// 2. **Keyboard**: ``ManagementModeMonitor`` consumes all keyDown events.
/// 3. **File drags**: ``ManagementModeDragShield`` registers for narrow file/media types
///    (frame-based routing, independent of hitTest). Agent studio custom types pass through
///    to SwiftUI's `.onDrop` on the outer hosting view.
/// 4. **Hover**: Subclasses override ``setContentInteractionEnabled(_:)`` for content-level
///    suppression (e.g., controller-managed WKUserScript + runtime JS for WKWebView panes,
///    Ghostty mouse guards for terminal surfaces).
///
/// Subclasses with custom hitTest (e.g. `AgentStudioTerminalView`) must
/// call `super.hitTest` first during management mode.
///
/// Subclasses:
/// - `AgentStudioTerminalView` — Ghostty/zmx terminal
/// - `WebviewPaneView` — embedded web content
/// - `BridgePaneView` — React bridge content
/// - `CodeViewerPaneView` — source code viewer (stub)
@MainActor
class PaneView: NSView, Identifiable {
    nonisolated let paneId: UUID
    nonisolated var id: UUID { paneId }

    /// Interaction shield that blocks all pane interaction during management mode.
    /// Installed as the topmost subview of this view.
    private(set) var interactionShield: ManagementModeDragShield?

    init(paneId: UUID) {
        self.paneId = paneId
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Hit Testing

    /// Blocks all AppKit mouse event routing during management mode.
    /// Returns `nil` so clicks are blocked and AppKit continues searching
    /// up to the outer hosting view where SwiftUI's `.onDrop` handles
    /// pane/tab drag operations.
    ///
    /// The interaction shield (subview) handles file/media drag suppression
    /// separately via NSDraggingDestination (bounds-based, independent of hitTest).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !ManagementModeMonitor.shared.isActive else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Content Interaction

    /// Called by the interaction shield when management mode activates/deactivates.
    /// Subclasses override to apply content-level interaction suppression.
    ///
    /// - `WebviewPaneView`: delegates to controller-managed persistent WKUserScript
    /// - `BridgePaneView`: delegates to controller-managed persistent WKUserScript
    /// - `AgentStudioTerminalView`: Ghostty mouse handlers have their own guards
    ///
    /// - Parameter enabled: `true` when management mode deactivates (normal interaction),
    ///   `false` when management mode activates (suppress interaction).
    func setContentInteractionEnabled(_ enabled: Bool) {
        // Base class no-op. Subclasses override for content-specific behavior.
    }

    // MARK: - Interaction Shield

    /// Installs the ``ManagementModeDragShield`` as the topmost subview.
    /// Called from ``swiftUIContainer`` after the pane's content views are
    /// set up by the subclass.
    private func installInteractionShield() {
        guard interactionShield == nil else { return }
        let shield = ManagementModeDragShield()
        shield.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shield)
        NSLayoutConstraint.activate([
            shield.topAnchor.constraint(equalTo: topAnchor),
            shield.leadingAnchor.constraint(equalTo: leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: trailingAnchor),
            shield.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        interactionShield = shield
    }

    // MARK: - SwiftUI Bridge

    /// SwiftUI bridge container. Returns a stable NSView wrapper for use with
    /// NSViewRepresentable. Terminal overrides this with its own implementation;
    /// non-terminal subclasses use the default.
    ///
    /// Uses `ManagementModeContainerView` which also overrides `hitTest` to
    /// return `nil` during management mode (belt-and-suspenders).
    ///
    /// Installs the interaction shield as the topmost subview of this PaneView.
    /// By the time swiftUIContainer is accessed, subclass init has already set
    /// up content views (WKWebView hosting view, Ghostty surface, etc.), so the
    /// shield sits above all content.
    private(set) lazy var swiftUIContainer: NSView = {
        let container = ManagementModeContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        self.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            self.topAnchor.constraint(equalTo: container.topAnchor),
            self.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Install interaction shield above all content subviews.
        installInteractionShield()

        return container
    }()
}
