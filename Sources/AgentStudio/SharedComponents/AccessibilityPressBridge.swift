import AppKit
import SwiftUI

struct AccessibilityPressBridge: NSViewRepresentable {
    let identifier: String
    let label: String
    let value: String?
    let isEnabled: Bool
    let action: @MainActor () -> Void

    init(
        identifier: String,
        label: String,
        value: String? = nil,
        isEnabled: Bool = true,
        action: @MainActor @escaping () -> Void
    ) {
        self.identifier = identifier
        self.label = label
        self.value = value
        self.isEnabled = isEnabled
        self.action = action
    }

    func makeNSView(context _: Context) -> AccessibilityPressBridgeView {
        let view = AccessibilityPressBridgeView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.label = label
        view.value = value
        view.isEnabled = isEnabled
        view.action = action
        return view
    }

    func updateNSView(_ nsView: AccessibilityPressBridgeView, context _: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.label = label
        nsView.value = value
        nsView.isEnabled = isEnabled
        nsView.action = action
    }
}

@MainActor
final class AccessibilityPressBridgeView: NSView {
    var label = ""
    var value: String?
    var isEnabled = true
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

    override func isAccessibilityEnabled() -> Bool {
        isEnabled
    }

    override func accessibilityLabel() -> String? {
        label
    }

    override func accessibilityValue() -> Any? {
        value
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        action()
        return true
    }
}
