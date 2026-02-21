import AppKit
import SwiftUI

/// NSViewRepresentable wrapping NSTextField that selects all text on initial focus.
/// Solves the SwiftUI TextField flicker problem: SwiftUI state mutations in focus
/// handlers cause re-renders that reset the field editor's selection. By handling
/// selection at the AppKit layer (in mouseDown), no SwiftUI state changes occur
/// and the selection is stable.
struct SelectAllTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void
    var onTextChange: ((String, String) -> Void)?

    func makeNSView(context: Context) -> SelectAllNSTextField {
        let field = SelectAllNSTextField()
        field.placeholderString = placeholder
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: SelectAllNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectAllTextField

        init(_ parent: SelectAllTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let oldValue = parent.text
            parent.text = field.stringValue
            parent.onTextChange?(oldValue, field.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                // Resign focus after submit
                control.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape key — resign focus
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}

/// NSTextField subclass that selects all text when first gaining focus via click.
/// Subsequent clicks while already focused position the cursor normally.
final class SelectAllNSTextField: NSTextField {
    private var justBecameFirstResponder = false

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            justBecameFirstResponder = true
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if justBecameFirstResponder {
            justBecameFirstResponder = false
            currentEditor()?.selectAll(self)
        }
    }
}
