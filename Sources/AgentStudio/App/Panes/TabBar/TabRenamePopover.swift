import AppKit
import SwiftUI

struct TabRenamePopover: View {
    let currentTitle: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var renameText: String
    @State private var isRenameFieldFocused = false

    init(currentTitle: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.currentTitle = currentTitle
        self.onCommit = onCommit
        self.onCancel = onCancel
        _renameText = State(initialValue: currentTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Tab")
                .font(.system(size: AppStyles.General.Typography.textXl, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                RenameWrappingTextField(
                    placeholder: "Tab name",
                    text: $renameText,
                    isFocused: $isRenameFieldFocused,
                    onCommit: commitRename,
                    onCancel: onCancel
                )
                .frame(minHeight: 112)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(AppStyles.General.Fill.subtle))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isRenameFieldFocused ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: isRenameFieldFocused ? 2 : 1
                        )
                }
            }

            Text("Long names wrap while editing. The saved tab title stays on one line.")
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()

                Button(LocalActionSpec.cancel.actionSpec.label, role: .cancel) {
                    onCancel()
                }

                Button(LocalActionSpec.rename.actionSpec.label, action: commitRename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedRenameText.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            renameText = currentTitle
        }
    }

    private var trimmedRenameText: String {
        Tab.normalizedName(renameText)
    }

    private func commitRename() {
        guard !trimmedRenameText.isEmpty else { return }
        onCommit(renameText)
    }
}

struct RenameWrappingTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RenameWrappingTextFieldContainer {
        let container = RenameWrappingTextFieldContainer(
            placeholder: placeholder,
            coordinator: context.coordinator
        )
        container.updateText(text)

        Task { @MainActor [weak container] in
            guard let container else { return }
            container.focusAndSelectAll()
        }

        return container
    }

    func updateNSView(_ nsView: RenameWrappingTextFieldContainer, context: Context) {
        nsView.placeholder = placeholder
        nsView.updateText(text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameWrappingTextField

        init(_ parent: RenameWrappingTextField) {
            self.parent = parent
        }

        @MainActor
        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        @MainActor
        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
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

final class RenameWrappingTextFieldContainer: NSView {
    private let textField = RenameWrappingField()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private weak var coordinator: RenameWrappingTextField.Coordinator?

    var placeholder: String {
        get { placeholderLabel.stringValue }
        set { placeholderLabel.stringValue = newValue }
    }

    init(placeholder: String, coordinator: RenameWrappingTextField.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        placeholderLabel.stringValue = placeholder
        configureViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    func updateText(_ newText: String) {
        guard textField.stringValue != newText else { return }
        textField.stringValue = newText
        syncPlaceholderVisibility()
    }

    func focusAndSelectAll() {
        guard window?.makeFirstResponder(textField) == true else { return }
        textField.selectText(nil)
    }

    func focusCaretAtEnd() {
        guard window?.makeFirstResponder(textField) == true else { return }
        guard let editor = textField.currentEditor() as? NSTextView else { return }
        let textLength = textField.stringValue.count
        editor.setSelectedRange(NSRange(location: textLength, length: 0))
    }

    var textFieldForTesting: NSTextField {
        textField
    }

    var selectedRangeForTesting: NSRange {
        (textField.currentEditor() as? NSTextView)?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    private func configureViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.delegate = coordinator
        textField.font = .systemFont(ofSize: AppStyles.General.Typography.textLg, weight: .medium)
        textField.textColor = .labelColor
        textField.alignment = .left
        textField.placeholderString = placeholder
        textField.focusRingType = .none
        textField.isBordered = false
        textField.drawsBackground = false
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.cell?.lineBreakMode = .byWordWrapping
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.usesSingleLineMode = false
        textField.coordinator = coordinator

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: AppStyles.General.Typography.textLg, weight: .medium)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.lineBreakMode = .byWordWrapping

        addSubview(textField)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),

            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        syncPlaceholderVisibility()
    }

    private func syncPlaceholderVisibility() {
        placeholderLabel.isHidden = !textField.stringValue.isEmpty
    }

    override func mouseDown(with event: NSEvent) {
        focusCaretAtEnd()
    }
}

final class RenameWrappingField: NSTextField {
    weak var coordinator: RenameWrappingTextField.Coordinator?

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            coordinator?.parent.isFocused = true
        }
        return didBecomeFirstResponder
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        coordinator?.parent.isFocused = false
    }
}
