import AppKit
import SwiftUI

package struct AccessibilityLabelBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    var exposesAccessibility = true

    package init(identifier: String, label: String, exposesAccessibility: Bool = true) {
        self.identifier = identifier
        self.label = label
        self.exposesAccessibility = exposesAccessibility
    }

    package func makeNSView(context _: Context) -> AccessibilityLabelBridgeView {
        let view = AccessibilityLabelBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.exposesAccessibility = exposesAccessibility
        return view
    }

    package func updateNSView(_ nsView: AccessibilityLabelBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.exposesAccessibility = exposesAccessibility
    }
}

@MainActor
package final class AccessibilityLabelBridgeView: NSView {
    var label = ""
    var exposesAccessibility = true

    package override func isAccessibilityElement() -> Bool {
        exposesAccessibility
    }

    package override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    package override func accessibilityIdentifier() -> String {
        guard exposesAccessibility else { return "" }
        return identifier?.rawValue ?? ""
    }

    package override func accessibilityLabel() -> String? {
        guard exposesAccessibility else { return nil }
        return label
    }
}
