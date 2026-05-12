import AppKit
import SwiftUI

struct AccessibilityPressBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    let action: @MainActor @Sendable () -> Void

    func makeNSView(context _: Context) -> AccessibilityPressBridgeView {
        let view = AccessibilityPressBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.action = action
        return view
    }

    func updateNSView(_ nsView: AccessibilityPressBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.action = action
    }
}

@MainActor
final class AccessibilityPressBridgeView: NSView {
    var label = ""
    var action: @MainActor @Sendable () -> Void = {}

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityIdentifier() -> String {
        identifier?.rawValue ?? ""
    }

    override func accessibilityLabel() -> String? {
        label
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}
