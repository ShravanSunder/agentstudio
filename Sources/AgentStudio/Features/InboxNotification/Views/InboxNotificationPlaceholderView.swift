import AppKit
import SwiftUI

enum InboxNotificationPlaceholderFocusPublisher {
    @MainActor
    static func publish(
        hasFocus: Bool,
        into uiState: UIStateAtom
    ) {
        uiState.setSidebarHasFocus(hasFocus)
    }
}

private final class InboxNotificationPlaceholderFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }

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
}

private struct InboxNotificationPlaceholderFocusBridge: NSViewRepresentable {
    let uiState: UIStateAtom

    func makeNSView(context: Context) -> InboxNotificationPlaceholderFocusableView {
        let view = InboxNotificationPlaceholderFocusableView()
        view.identifier = InboxNotificationPlaceholderView.focusTargetIdentifier
        view.onFocusChange = { hasFocus in
            InboxNotificationPlaceholderFocusPublisher.publish(
                hasFocus: hasFocus,
                into: uiState
            )
        }
        return view
    }

    func updateNSView(
        _ nsView: InboxNotificationPlaceholderFocusableView,
        context: Context
    ) {
        nsView.onFocusChange = { hasFocus in
            InboxNotificationPlaceholderFocusPublisher.publish(
                hasFocus: hasFocus,
                into: uiState
            )
        }
    }

    static func dismantleNSView(
        _ nsView: InboxNotificationPlaceholderFocusableView,
        coordinator: ()
    ) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
    }
}

struct InboxNotificationPlaceholderView: View {
    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier(
        "InboxNotificationPlaceholderView.focusTarget"
    )

    let uiState: UIStateAtom

    var body: some View {
        VStack(spacing: 12) {
            InboxNotificationPlaceholderFocusBridge(uiState: uiState)
                .frame(width: 1, height: 1)
                .opacity(0.001)

            Image(systemName: "bell.slash")
                .imageScale(.large)
                .foregroundStyle(.secondary)

            Text("Inbox")
                .font(.headline)

            Text("No notifications yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
