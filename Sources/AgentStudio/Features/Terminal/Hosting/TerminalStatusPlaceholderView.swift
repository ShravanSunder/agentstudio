import AppKit

@MainActor
/// Placeholder direction matters:
/// `.preparing` is a transient waiting-for-geometry state, while
/// `.failedToStart` is the resting startup-failure state until the user retries or closes.
enum TerminalStatusPlaceholderMode: Equatable {
    case preparing
    case failedToStart
}

@MainActor
final class TerminalStatusPlaceholderView: NSView, PaneMountedContent {
    let paneId: UUID
    private let title: String
    private let startupOverlay = SurfaceStartupOverlayView()
    private let errorOverlay = SurfaceErrorOverlayView()
    private let onRetryRequested: ((UUID) -> Void)?
    private let onDismissRequested: ((UUID) -> Void)?
    private(set) var mode: TerminalStatusPlaceholderMode

    init(
        paneId: UUID,
        title: String,
        mode: TerminalStatusPlaceholderMode,
        onRetryRequested: ((UUID) -> Void)? = nil,
        onDismissRequested: ((UUID) -> Void)? = nil
    ) {
        self.paneId = paneId
        self.title = title
        self.mode = mode
        self.onRetryRequested = onRetryRequested
        self.onDismissRequested = onDismissRequested
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupSubviews()
        render(mode: mode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    var shouldRetryCreationWhenBoundsChange: Bool {
        mode == .preparing
    }

    func setContentInteractionEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func configure(mode: TerminalStatusPlaceholderMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        render(mode: mode)
    }

    private func setupSubviews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        startupOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(startupOverlay)
        NSLayoutConstraint.activate([
            startupOverlay.topAnchor.constraint(equalTo: topAnchor),
            startupOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            startupOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            startupOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        errorOverlay.onRestart = { [weak self] in
            guard let self else { return }
            self.onRetryRequested?(self.paneId)
        }
        errorOverlay.onDismiss = { [weak self] in
            guard let self else { return }
            self.onDismissRequested?(self.paneId)
        }
        addSubview(errorOverlay)
        NSLayoutConstraint.activate([
            errorOverlay.topAnchor.constraint(equalTo: topAnchor),
            errorOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            errorOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            errorOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func render(mode: TerminalStatusPlaceholderMode) {
        switch mode {
        case .preparing:
            errorOverlay.hide()
            startupOverlay.showPreparing()
        case .failedToStart:
            startupOverlay.hide()
            errorOverlay.configure(health: .unhealthy(reason: .initializationFailed))
        }
    }
}
