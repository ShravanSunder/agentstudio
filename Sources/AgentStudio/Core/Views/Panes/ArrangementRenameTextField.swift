import AppKit
import SwiftUI

struct ArrangementRenameTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: NSFont
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ArrangementRenameNSTextField {
        let field = ArrangementRenameNSTextField()
        field.delegate = context.coordinator
        field.coordinator = context.coordinator
        field.onCommit = onCommit
        field.onCancel = onCancel
        field.stringValue = text
        configure(field)

        Task { @MainActor [weak field] in
            guard let field else { return }
            field.focusAndSelectAll()
        }

        return field
    }

    func updateNSView(_ nsView: ArrangementRenameNSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.delegate = context.coordinator
        nsView.coordinator = context.coordinator
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        configure(nsView)

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if isFocused, nsView.window?.firstResponder !== nsView.currentEditor() {
            Task { @MainActor [weak nsView] in
                nsView?.focusAndSelectAll()
            }
        }
    }

    private func configure(_ field: ArrangementRenameNSTextField) {
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = .labelColor
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.lineBreakMode = .byClipping
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ArrangementRenameTextField

        init(_ parent: ArrangementRenameTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
            guard let field = obj.object as? NSTextField,
                let editor = field.currentEditor() as? NSTextView
            else { return }
            editor.selectAll(nil)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                #selector(NSResponder.insertLineBreak(_:)):
                parent.onCommit()
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

final class ArrangementRenameNSTextField: NSTextField {
    weak var coordinator: ArrangementRenameTextField.Coordinator?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    func focusAndSelectAll() {
        guard window?.makeFirstResponder(self) == true else { return }
        currentEditor()?.selectAll(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        consumeArrangementRenameCommand(from: event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if consumeArrangementRenameCommand(from: event) {
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
        window?.makeFirstResponder(nil)
    }

    @discardableResult
    private func consumeArrangementRenameCommand(from event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let charactersIgnoringModifiers = event.charactersIgnoringModifiers ?? ""
        if ArrangementRenameEditorKey.commitCharacters.contains(charactersIgnoringModifiers)
            || ArrangementRenameEditorKey.commitKeyCodes.contains(event.keyCode)
        {
            onCommit?()
            window?.makeFirstResponder(nil)
            return true
        }

        if charactersIgnoringModifiers == ArrangementRenameEditorKey.cancelCharacter
            || event.keyCode == ArrangementRenameEditorKey.cancelKeyCode
        {
            onCancel?()
            window?.makeFirstResponder(nil)
            return true
        }

        return false
    }
}

private enum ArrangementRenameEditorKey {
    static let commitCharacters: Set<String> = ["\r", "\u{3}"]
    static let commitKeyCodes: Set<UInt16> = [36, 76]
    static let cancelCharacter = "\u{1b}"
    static let cancelKeyCode: UInt16 = 53
}
