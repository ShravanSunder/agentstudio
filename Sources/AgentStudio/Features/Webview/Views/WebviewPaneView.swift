import AppKit
import SwiftUI

/// Webview pane embedding a real browser via SwiftUI WebView/WebPage.
///
/// Ownership: WebviewPaneView (NSView/PaneView) holds a strong reference to
/// `WebviewPaneController` (@Observable @MainActor). An `NSHostingView` wraps
/// the SwiftUI `WebviewPaneContentView` which observes the controller.
/// Controller lifetime is tied to this NSView's lifetime in the AppKit layout hierarchy.
final class WebviewPaneView: PaneView {
    let controller: WebviewPaneController
    private var hostingView: NSHostingView<WebviewPaneContentView>?
    private var suspendedDragTypesByView: [ObjectIdentifier: (view: NSView, types: [NSPasteboard.PasteboardType])] = [:]

    init(paneId: UUID, state: WebviewState) {
        self.controller = WebviewPaneController(paneId: paneId, state: state)
        super.init(paneId: paneId)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncHostingViewFrame()
    }

    override func layout() {
        super.layout()
        syncHostingViewFrame()
        if ManagementModeMonitor.shared.isActive {
            suspendDescendantDragRegistrationsIfNeeded()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setContentInteractionEnabled(!ManagementModeMonitor.shared.isActive)
        syncHostingViewFrame()
    }

    /// Capture current tab state for persistence.
    func currentState() -> WebviewState {
        controller.snapshot()
    }

    // MARK: - Content Interaction

    /// Delegates management mode interaction suppression to the controller's
    /// persistent user-script pipeline (current document + future navigations).
    override func setContentInteractionEnabled(_ enabled: Bool) {
        if enabled {
            restoreDescendantDragRegistrationsIfNeeded()
        } else {
            suspendDescendantDragRegistrationsIfNeeded()
        }
        controller.setWebContentInteractionEnabled(enabled)
    }

    // MARK: - Setup

    private func setupHostingView() {
        let contentView = WebviewPaneContentView(controller: controller)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        self.hostingView = hosting
        syncHostingViewFrame()
    }

    private func syncHostingViewFrame() {
        guard let hostingView else { return }
        if hostingView.frame != bounds {
            hostingView.frame = bounds
        }
        hostingView.layoutSubtreeIfNeeded()
    }

    private func suspendDescendantDragRegistrationsIfNeeded() {
        guard let hostingView else { return }
        var stack: [NSView] = [hostingView]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)

            let identifier = ObjectIdentifier(view)
            if suspendedDragTypesByView[identifier] != nil {
                continue
            }

            let registeredTypes = view.registeredDraggedTypes
            guard !registeredTypes.isEmpty else { continue }

            suspendedDragTypesByView[identifier] = (view, registeredTypes)
            view.unregisterDraggedTypes()
        }
    }

    private func restoreDescendantDragRegistrationsIfNeeded() {
        guard !suspendedDragTypesByView.isEmpty else { return }
        for (_, registration) in suspendedDragTypesByView {
            guard !registration.types.isEmpty else { continue }
            registration.view.registerForDraggedTypes(registration.types)
        }
        suspendedDragTypesByView.removeAll(keepingCapacity: true)
    }
}
