import AppKit
import SwiftUI

struct TransientKeyboardSurfaceDismissBridge: NSViewRepresentable {
    let policy: TransientKeyboardSurfacePolicy
    let isEnabled: Bool
    let onDismiss: (() -> Void)?

    func makeNSView(context _: Context) -> TransientKeyboardSurfaceDismissCapturingView {
        let view = TransientKeyboardSurfaceDismissCapturingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: TransientKeyboardSurfaceDismissCapturingView, context _: Context) {
        update(nsView)
    }

    private func update(_ view: TransientKeyboardSurfaceDismissCapturingView) {
        view.policy = policy
        view.isEnabled = isEnabled
        view.onDismiss = onDismiss
    }
}

final class TransientKeyboardSurfaceDismissCapturingView: NSView {
    var policy: TransientKeyboardSurfacePolicy = .blocking
    var isEnabled = false
    var onDismiss: (() -> Void)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            teardownMonitor()
            return
        }

        installMonitorIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        guard apply(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if apply(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender

        guard isEnabled, policy.consumesEscape, onDismiss != nil else {
            super.cancelOperation(sender)
            return
        }

        onDismiss?()
    }

    private func apply(_ event: NSEvent) -> Bool {
        guard isEnabled, onDismiss != nil else { return false }
        guard let trigger = ShortcutDecoder.decode(event: event) else { return false }
        guard TransientKeyboardSurfaceDismissRouter.shouldDismiss(trigger: trigger, policy: policy) else {
            return false
        }

        onDismiss?()
        return true
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.eventBelongsToThisSurface(event) else { return event }
            return self.apply(event) ? nil : event
        }
    }

    // AppKit removes the view from its window before teardown, which gives us
    // a main-actor cleanup point. Do not move this into deinit; the monitor
    // token is non-Sendable under Swift 6 strict concurrency.
    private func teardownMonitor() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }

    private func eventBelongsToThisSurface(_ event: NSEvent) -> Bool {
        guard let surfaceWindow = window else { return false }

        if let eventWindow = event.window {
            return eventWindow == surfaceWindow
                || eventWindow.parent == surfaceWindow
                || surfaceWindow.parent == eventWindow
        }

        if event.windowNumber != 0 {
            return event.windowNumber == surfaceWindow.windowNumber
        }

        if let keyWindow = NSApp.keyWindow {
            return keyWindow == surfaceWindow
                || keyWindow.parent == surfaceWindow
                || surfaceWindow.parent == keyWindow
        }

        return false
    }
}
