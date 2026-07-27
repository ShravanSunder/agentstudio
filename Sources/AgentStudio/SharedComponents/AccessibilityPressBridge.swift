import AppKit
import SwiftUI

package struct AccessibilityPressBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    let action: @MainActor () -> Void

    package init(identifier: String, label: String, action: @escaping @MainActor () -> Void) {
        self.identifier = identifier
        self.label = label
        self.action = action
    }

    package func makeNSView(context _: Context) -> AccessibilityPressBridgeView {
        let view = AccessibilityPressBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.action = action
        return view
    }

    package func updateNSView(_ nsView: AccessibilityPressBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.action = action
    }
}

@MainActor
package final class AccessibilityPressBridgeView: NSView {
    var label = ""
    var action: @MainActor () -> Void = {}

    package override func isAccessibilityElement() -> Bool {
        true
    }

    package override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    package override func accessibilityIdentifier() -> String {
        identifier?.rawValue ?? ""
    }

    package override func accessibilityLabel() -> String? {
        label
    }

    package override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}
