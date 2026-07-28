import AppKit
import SwiftUI

package struct AccessibilityLabelBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    var role: NSAccessibility.Role = .group
    var help: String?
    var selected: Bool?
    var exposesAccessibility = true

    package init(
        identifier: String,
        label: String,
        role: NSAccessibility.Role = .group,
        help: String? = nil,
        selected: Bool? = nil,
        exposesAccessibility: Bool = true
    ) {
        self.identifier = identifier
        self.label = label
        self.role = role
        self.help = help
        self.selected = selected
        self.exposesAccessibility = exposesAccessibility
    }

    package func makeNSView(context _: Context) -> AccessibilityLabelBridgeView {
        let view = AccessibilityLabelBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.role = role
        view.help = help
        view.selected = selected
        view.exposesAccessibility = exposesAccessibility
        return view
    }

    package func updateNSView(_ nsView: AccessibilityLabelBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.role = role
        nsView.help = help
        nsView.selected = selected
        nsView.exposesAccessibility = exposesAccessibility
    }
}

@MainActor
package final class AccessibilityLabelBridgeView: NSView {
    var label = ""
    var role: NSAccessibility.Role = .group
    var help: String?
    var selected: Bool?
    var exposesAccessibility = true

    package override func isAccessibilityElement() -> Bool {
        exposesAccessibility
    }

    package override func accessibilityRole() -> NSAccessibility.Role? {
        role
    }

    package override func accessibilityIdentifier() -> String {
        guard exposesAccessibility else { return "" }
        return identifier?.rawValue ?? ""
    }

    package override func accessibilityLabel() -> String? {
        guard exposesAccessibility else { return nil }
        return label
    }

    package override func accessibilityHelp() -> String? {
        guard exposesAccessibility else { return nil }
        return help ?? super.accessibilityHelp()
    }

    package override func isAccessibilitySelected() -> Bool {
        guard exposesAccessibility else { return false }
        return selected ?? super.isAccessibilitySelected()
    }
}
