import AppKit

/// Remembers the responder that should regain focus after keyboard-driven sidebar use.
@MainActor
final class SidebarReturnFocusOrigin {
    private weak var responderView: NSView?

    func captureCurrentResponder(in window: NSWindow, sidebarRoot: NSView?) {
        let candidate = Self.normalizedResponder(window.firstResponder)
        guard !Self.belongsToSidebar(candidate, sidebarRoot: sidebarRoot) else { return }
        responderView = candidate
    }

    func currentResponderBelongsToSidebar(in window: NSWindow, sidebarRoot: NSView?) -> Bool {
        Self.belongsToSidebar(
            Self.normalizedResponder(window.firstResponder),
            sidebarRoot: sidebarRoot
        )
    }

    @discardableResult
    func restore(in window: NSWindow?, fallback: () -> Void) -> Bool {
        let returnResponderView = responderView
        responderView = nil

        guard
            let window,
            let returnResponderView,
            returnResponderView.window === window,
            returnResponderView.acceptsFirstResponder,
            !returnResponderView.isHiddenOrHasHiddenAncestor,
            window.makeFirstResponder(returnResponderView)
        else {
            fallback()
            return false
        }
        return true
    }

    func clear() {
        responderView = nil
    }

    private static func normalizedResponder(_ responder: NSResponder?) -> NSView? {
        guard let textView = responder as? NSTextView, textView.isFieldEditor else {
            return responder as? NSView
        }
        return textView.delegate as? NSView
    }

    private static func belongsToSidebar(_ responderView: NSView?, sidebarRoot: NSView?) -> Bool {
        guard let responderView, let sidebarRoot else { return false }
        return responderView === sidebarRoot || responderView.isDescendant(of: sidebarRoot)
    }
}
