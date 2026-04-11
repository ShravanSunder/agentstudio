import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TabRenamePopoverTests {
    @Test
    func clickingEmptyEditorSpace_focusesFieldAndPlacesCaretAtEnd() {
        var text = "agent-vm | live-validation-2 | agent-vm"
        var isFocused = false

        let representable = RenameWrappingTextField(
            placeholder: "Tab name",
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            ),
            onCommit: {},
            onCancel: {}
        )
        let coordinator = representable.makeCoordinator()
        let container = RenameWrappingTextFieldContainer(
            placeholder: "Tab name",
            coordinator: coordinator
        )
        container.frame = NSRect(x: 0, y: 0, width: 420, height: 112)
        container.updateText(text)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView?.addSubview(container)

        let clickEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 200, y: 56),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        container.mouseDown(with: clickEvent!)

        #expect(isFocused)
        #expect(window.firstResponder === container.textFieldForTesting.currentEditor())
        #expect(container.selectedRangeForTesting.location == text.count)
        #expect(container.selectedRangeForTesting.length == 0)
    }
}
