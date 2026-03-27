import AppKit

/// Container NSView that blocks all AppKit event routing to pane content
/// during management mode. When `hitTest` returns `nil`, the entire subtree
/// becomes invisible to AppKit.
@MainActor
final class ManagementModeContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !ManagementModeMonitor.shared.isActive else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
protocol PaneMountedContent: NSView {
    func setContentInteractionEnabled(_ enabled: Bool)
}

@MainActor
class PaneHostView: NSView, Identifiable {
    nonisolated let paneId: UUID
    nonisolated var id: UUID { paneId }

    private(set) var interactionShield: ManagementModeDragShield?
    private let contentContainerView = NSView(frame: .zero)

    init(paneId: UUID) {
        self.paneId = paneId
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupContentContainerView()
        installInteractionShield()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard let window, let mountedContentView else {
            return super.becomeFirstResponder()
        }

        if mountedContentView.acceptsFirstResponder {
            return window.makeFirstResponder(mountedContentView)
        }

        return super.becomeFirstResponder()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !ManagementModeMonitor.shared.isActive else { return nil }
        return super.hitTest(point)
    }

    func mountContentView(_ mountedView: NSView & PaneMountedContent) {
        unmountContentView()

        mountedView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(mountedView)
        NSLayoutConstraint.activate([
            mountedView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            mountedView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            mountedView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            mountedView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
    }

    func unmountContentView() {
        for subview in contentContainerView.subviews {
            subview.removeFromSuperview()
        }
    }

    var mountedContentView: NSView? {
        contentContainerView.subviews.first
    }

    func mountedContent<MountedContent: NSView>(as _: MountedContent.Type = MountedContent.self)
        -> MountedContent?
    {
        mountedContentView as? MountedContent
    }

    func setContentInteractionEnabled(_ enabled: Bool) {
        for subview in contentContainerView.subviews {
            (subview as? PaneMountedContent)?.setContentInteractionEnabled(enabled)
        }
    }

    private func setupContentContainerView() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainerView)
        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

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

// MARK: - Testing

@MainActor
extension PaneHostView {
    var interactionShieldForTesting: ManagementModeDragShield? { interactionShield }
    var contentContainerViewForTesting: NSView { contentContainerView }
    var mountedContentViewForTesting: NSView? { mountedContentView }
}
