import AppKit
import SwiftUI

struct AccessibilityLabelBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    var role: NSAccessibility.Role = .group
    var help: String?
    var selected: Bool?
    var exposesAccessibility = true

    func makeNSView(context _: Context) -> AccessibilityLabelBridgeView {
        let view = AccessibilityLabelBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.role = role
        view.help = help
        view.selected = selected
        view.exposesAccessibility = exposesAccessibility
        return view
    }

    func updateNSView(_ nsView: AccessibilityLabelBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.role = role
        nsView.help = help
        nsView.selected = selected
        nsView.exposesAccessibility = exposesAccessibility
    }
}

@MainActor
final class AccessibilityLabelBridgeView: NSView {
    var label = ""
    var role: NSAccessibility.Role = .group
    var help: String?
    var selected: Bool?
    var exposesAccessibility = true

    override func isAccessibilityElement() -> Bool {
        exposesAccessibility
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        role
    }

    override func accessibilityIdentifier() -> String {
        guard exposesAccessibility else { return "" }
        return identifier?.rawValue ?? ""
    }

    override func accessibilityLabel() -> String? {
        guard exposesAccessibility else { return nil }
        return label
    }

    override func accessibilityHelp() -> String? {
        guard exposesAccessibility else { return nil }
        return help ?? super.accessibilityHelp()
    }

    override func isAccessibilitySelected() -> Bool {
        guard exposesAccessibility else { return false }
        return selected ?? super.isAccessibilitySelected()
    }
}
