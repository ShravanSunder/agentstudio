import AppKit

/// Stub view for embedded web content panes.
/// Displays a placeholder until WKWebView integration is implemented.
final class WebviewPaneView: PaneView {
    private let state: WebviewState

    init(paneId: UUID, state: WebviewState) {
        self.state = state
        super.init(paneId: paneId)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupPlaceholder() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let label = NSTextField(labelWithString: "Webview: \(state.url.absoluteString)")
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
