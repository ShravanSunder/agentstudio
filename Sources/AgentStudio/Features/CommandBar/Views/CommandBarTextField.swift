import AppKit
import SwiftUI

// MARK: - CommandBarTextField

/// NSViewRepresentable wrapping NSTextField for keyboard interception.
/// Captures arrow keys, Enter, Escape, and Backspace before SwiftUI default handling.
struct CommandBarTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: (EnterModifier) -> Void
    let onShortcutTrigger: (ShortcutTrigger) -> Bool
    let onBackspaceOnEmpty: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> KeyInterceptingTextField {
        let field = KeyInterceptingTextField()
        field.delegate = context.coordinator
        field.coordinator = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.lineBreakMode = .byClipping

        // Become first responder on next run loop
        Task { @MainActor [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ nsView: KeyInterceptingTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
            if let editor = nsView.currentEditor() as? NSTextView {
                editor.setSelectedRange(NSRange(location: text.count, length: 0))
            }
        }
        nsView.placeholderString = placeholder
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandBarTextField

        init(_ parent: CommandBarTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Called when the field editor is set up (field gains focus).
        /// Deselect all text and place cursor at end.
        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                let editor = field.currentEditor() as? NSTextView
            else { return }
            let len = field.stringValue.count
            editor.setSelectedRange(NSRange(location: len, length: 0))
        }

        /// Intercept special keys before the text field handles them.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                #selector(NSResponder.insertLineBreak(_:)):
                let flags = NSApplication.shared.currentEvent?.modifierFlags ?? []
                // Modified Enter normally gets consumed earlier by the panel's
                // performKeyEquivalent path. Keep this selector-based fallback
                // so NSTextField command routing still reaches the same shortcut
                // handler when AppKit sends text-system commands instead.
                if let trigger = Self.shortcutTrigger(
                    for: commandSelector,
                    modifierFlags: flags
                ) {
                    return parent.onShortcutTrigger(trigger)
                }
                guard
                    let modifier = Self.enterModifier(
                        for: commandSelector,
                        modifierFlags: flags
                    )
                else { return false }
                handleEnter(modifier)
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                if textView.string.isEmpty {
                    parent.onBackspaceOnEmpty()
                    return true
                }
                return false
            default:
                return false
            }
        }

        @MainActor
        func handleEnter(_ modifier: EnterModifier) {
            parent.onEnter(modifier)
        }

        static func shortcutTrigger(
            for commandSelector: Selector,
            modifierFlags: NSEvent.ModifierFlags
        ) -> ShortcutTrigger? {
            switch commandSelector {
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return .init(key: .enter, modifiers: [.option])
            case #selector(NSResponder.insertLineBreak(_:)):
                if modifierFlags.contains(.option) {
                    return .init(key: .enter, modifiers: [.option])
                }
                if modifierFlags.contains(.command) {
                    return .init(key: .enter, modifiers: [.command])
                }
                return nil
            case #selector(NSResponder.insertNewline(_:)):
                if modifierFlags.contains(.command) {
                    return .init(key: .enter, modifiers: [.command])
                }
                if modifierFlags.contains(.option) {
                    return .init(key: .enter, modifiers: [.option])
                }
                return nil
            default:
                return nil
            }
        }

        static func enterModifier(
            for commandSelector: Selector,
            modifierFlags: NSEvent.ModifierFlags
        ) -> EnterModifier? {
            if let trigger = shortcutTrigger(
                for: commandSelector,
                modifierFlags: modifierFlags
            ) {
                if trigger.modifiers.contains(.command) {
                    return .command
                }
                if trigger.modifiers.contains(.option) {
                    return .option
                }
            }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return .plain
            default:
                return nil
            }
        }
    }
}

// MARK: - KeyInterceptingTextField

/// NSTextField subclass that forwards key events through the coordinator.
final class KeyInterceptingTextField: NSTextField {
    weak var coordinator: CommandBarTextField.Coordinator?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // After becoming first responder, deselect text and place cursor at end.
        // Use async to let the field editor finish setup.
        if result {
            Task { @MainActor [weak self] in
                guard let self, let editor = self.currentEditor() as? NSTextView else { return }
                let len = self.stringValue.count
                editor.setSelectedRange(NSRange(location: len, length: 0))
            }
        }
        return result
    }
}
