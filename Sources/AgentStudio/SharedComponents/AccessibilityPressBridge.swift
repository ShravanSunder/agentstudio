import AppKit
import SwiftUI

struct AccessibilityPressBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    var help: String?
    let action: @MainActor () -> Void

    func makeNSView(context _: Context) -> AccessibilityPressBridgeView {
        let view = AccessibilityPressBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.help = help
        view.action = action
        return view
    }

    func updateNSView(_ nsView: AccessibilityPressBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.help = help
        nsView.action = action
    }
}

@MainActor
final class AccessibilityPressBridgeView: NSView {
    var label = ""
    var help: String?
    var action: @MainActor () -> Void = {}

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

    override func accessibilityHelp() -> String? {
        help ?? super.accessibilityHelp()
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}
