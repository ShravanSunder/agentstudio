import AppKit

/// Base class for all pane views that can appear in the split tree.
/// Provides the common identity (paneId) and SwiftUI bridging contract.
///
/// Subclasses:
/// - `AgentStudioTerminalView` — Ghostty/tmux terminal
/// - `WebviewPaneView` — embedded web content (stub)
/// - `CodeViewerPaneView` — source code viewer (stub)
class PaneView: NSView, Identifiable {
    let paneId: UUID
    var id: UUID { paneId }

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
    private(set) lazy var swiftUIContainer: NSView = {
        let container = NSView()
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
