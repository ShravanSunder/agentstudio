import AppKit

/// Stub view for source code viewer panes.
/// Displays a placeholder until NSTextView-based implementation is added.
final class CodeViewerPaneView: PaneView {
    private let state: CodeViewerState

    init(paneId: UUID, state: CodeViewerState) {
        self.state = state
        super.init(paneId: paneId)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupPlaceholder() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let label = NSTextField(labelWithString: "Code Viewer: \(state.filePath.lastPathComponent)")
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
