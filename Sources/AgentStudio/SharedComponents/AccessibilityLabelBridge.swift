import AppKit
import SwiftUI

struct AccessibilityLabelBridge: NSViewRepresentable {
    let identifier: String
    let label: String

    func makeNSView(context _: Context) -> AccessibilityLabelBridgeView {
        let view = AccessibilityLabelBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        return view
    }

    func updateNSView(_ nsView: AccessibilityLabelBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
    }
}

@MainActor
final class AccessibilityLabelBridgeView: NSView {
    var label = ""

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityIdentifier() -> String {
        identifier?.rawValue ?? ""
    }

    override func accessibilityLabel() -> String? {
        label
    }
}
