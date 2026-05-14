import AppKit
import SwiftUI

final class InboxNotificationSidebarFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }
    var onEscape: @MainActor @Sendable () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange(false)
        }
        return didResignFirstResponder
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        onEscape()
    }
}

struct InboxNotificationSidebarFocusBridge: NSViewRepresentable {
    let uiState: UIStateAtom
    let onEscape: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> InboxNotificationSidebarFocusableView {
        let view = InboxNotificationSidebarFocusableView()
        view.identifier = InboxNotificationSidebarView.focusTargetIdentifier
        view.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: InboxNotificationSidebarFocusableView, context: Context) {
        nsView.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: InboxNotificationSidebarFocusableView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
    }
}
