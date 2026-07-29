import AppKit
import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

@MainActor
@Suite(.serialized)
struct AccessibilityPressBridgeTests {
    @Test("disabled accessibility press bridge exposes disabled state and rejects press")
    func disabledAccessibilityPressBridgeRejectsPress() {
        var pressCount = 0
        let hostingView = NSHostingView(
            rootView: AccessibilityPressBridge(
                identifier: "disabled-press-probe",
                label: "Disabled probe",
                isEnabled: false
            ) {
                pressCount += 1
            }
            .frame(width: 40, height: 40)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()

        guard let bridgeView = firstAccessibilityPressBridgeView(in: hostingView) else {
            Issue.record("Mounted accessibility press bridge must expose its backing NSView")
            return
        }
        #expect(bridgeView.accessibilityIdentifier() == "disabled-press-probe")
        #expect(!bridgeView.isAccessibilityEnabled())
        #expect(!bridgeView.accessibilityPerformPress())
        #expect(pressCount == 0)
    }
}

@MainActor
private func firstAccessibilityPressBridgeView(in root: NSView) -> AccessibilityPressBridgeView? {
    if let bridgeView = root as? AccessibilityPressBridgeView {
        return bridgeView
    }
    for subview in root.subviews {
        if let bridgeView = firstAccessibilityPressBridgeView(in: subview) {
            return bridgeView
        }
    }
    return nil
}
