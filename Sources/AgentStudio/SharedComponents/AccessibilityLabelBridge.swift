import AppKit
import SwiftUI

struct AccessibilityLabelBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    var exposesAccessibility = true

    func makeNSView(context _: Context) -> AccessibilityLabelBridgeView {
        let view = AccessibilityLabelBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.exposesAccessibility = exposesAccessibility
        return view
    }

    func updateNSView(_ nsView: AccessibilityLabelBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.exposesAccessibility = exposesAccessibility
    }
}

@MainActor
final class AccessibilityLabelBridgeView: NSView {
    var label = ""
    var exposesAccessibility = true

    override func isAccessibilityElement() -> Bool {
        exposesAccessibility
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityIdentifier() -> String {
        guard exposesAccessibility else { return "" }
        return identifier?.rawValue ?? ""
    }

    override func accessibilityLabel() -> String? {
        guard exposesAccessibility else { return nil }
        return label
    }
}
