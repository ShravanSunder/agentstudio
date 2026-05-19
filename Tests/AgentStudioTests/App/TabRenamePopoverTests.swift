import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TabRenamePopoverTests {
    @Test
    func renameEditorUsesInsetTextViewForWrappedEditing() {
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

        let textEditor = container.textEditorForTesting

        #expect(textEditor.textContainerInset.width >= 10)
        #expect(textEditor.textContainerInset.height >= 10)
        #expect(textEditor.textContainer?.lineFragmentPadding == 0)
        #expect(textEditor.textContainer?.widthTracksTextView == true)
        #expect(textEditor.isHorizontallyResizable == false)
    }

    @Test
    func renameEditorConsumesReturnEnterAndEscapeCommands() {
        var text = "agent-vm | live-validation-2 | agent-vm"
        var isFocused = false
        var commitCount = 0
        var cancelCount = 0

        let container = makeContainer(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            ),
            onCommit: { commitCount += 1 },
            onCancel: { cancelCount += 1 }
        )

        #expect(container.performKeyEquivalent(with: keyDown("\r", keyCode: 0)))
        #expect(commitCount == 1)
        #expect(cancelCount == 0)

        #expect(container.performKeyEquivalent(with: keyDown("\r", keyCode: 0, modifiers: .command)))
        #expect(commitCount == 2)
        #expect(cancelCount == 0)

        #expect(container.performKeyEquivalent(with: keyDown("\u{3}", keyCode: 0)))
        #expect(commitCount == 3)
        #expect(cancelCount == 0)

        #expect(container.performKeyEquivalent(with: keyDown("\u{1b}", keyCode: 0)))
        #expect(commitCount == 3)
        #expect(cancelCount == 1)
    }

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
        #expect(window.firstResponder === container.textEditorForTesting)
        #expect(container.selectedRangeForTesting.location == text.count)
        #expect(container.selectedRangeForTesting.length == 0)
    }

    private func makeContainer(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> RenameWrappingTextFieldContainer {
        let representable = RenameWrappingTextField(
            placeholder: "Tab name",
            text: text,
            isFocused: isFocused,
            onCommit: onCommit,
            onCancel: onCancel
        )
        let coordinator = representable.makeCoordinator()
        let container = RenameWrappingTextFieldContainer(
            placeholder: "Tab name",
            coordinator: coordinator
        )
        container.updateText(text.wrappedValue)
        return container
    }

    private func keyDown(
        _ characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
