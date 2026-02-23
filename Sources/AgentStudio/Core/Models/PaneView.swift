import AppKit

/// Container NSView that blocks all AppKit event routing to pane content
/// during management mode. When `hitTest` returns `nil`, the entire subtree
/// (terminal surfaces, WKWebView, etc.) becomes invisible to AppKit — no
/// clicks, keyboard events, or drag destinations are delivered.
///
/// SwiftUI controls above the `NSViewRepresentable` in the ZStack
/// (management buttons, drag handle, `.onDrop` overlay) are unaffected
/// because they operate at the SwiftUI/hosting view level.
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
/// Subclasses:
/// - `AgentStudioTerminalView` — Ghostty/zmx terminal
/// - `WebviewPaneView` — embedded web content (stub)
/// - `CodeViewerPaneView` — source code viewer (stub)
@MainActor
class PaneView: NSView, Identifiable {
    nonisolated let paneId: UUID
    nonisolated var id: UUID { paneId }

    init(paneId: UUID) {
        self.paneId = paneId
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    /// SwiftUI bridge container. Returns a stable NSView wrapper for use with
    /// NSViewRepresentable. Terminal overrides this with its own implementation;
    /// non-terminal subclasses use the default.
    ///
    /// Uses `ManagementModeContainerView` which overrides `hitTest` to return
    /// `nil` during management mode, blocking all AppKit events (clicks, drags,
    /// keyboard) from reaching pane content.
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

        return container
    }()
}
