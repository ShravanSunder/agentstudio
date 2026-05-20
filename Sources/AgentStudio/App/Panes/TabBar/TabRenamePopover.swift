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

            Text("Saved titles display on one line.")
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
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.placeholder = placeholder
        nsView.updateText(text)
    }

    final class Coordinator {
        var parent: RenameWrappingTextField

        init(_ parent: RenameWrappingTextField) {
            self.parent = parent
        }
    }
}

final class RenameWrappingTextFieldContainer: NSView {
    private let textView = RenameWrappingTextView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    var coordinator: RenameWrappingTextField.Coordinator {
        didSet {
            configureTextViewCallbacks()
        }
    }

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
        guard textView.string != newText else { return }
        textView.string = newText
        syncPlaceholderVisibility()
    }

    func focusAndSelectAll() {
        guard window?.makeFirstResponder(textView) == true else { return }
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
    }

    func focusCaretAtEnd() {
        guard window?.makeFirstResponder(textView) == true else { return }
        let textLength = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: textLength, length: 0))
    }

    var textEditorForTesting: NSTextView {
        textView
    }

    var selectedRangeForTesting: NSRange {
        textView.selectedRange()
    }

    private func configureViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: AppStyles.General.Typography.textLg, weight: .medium)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        configureTextViewCallbacks()

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: AppStyles.General.Typography.textLg, weight: .medium)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false

        addSubview(textView)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        syncPlaceholderVisibility()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        textView.consumeRenameCommand(from: event)
    }

    private func syncPlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    private func configureTextViewCallbacks() {
        textView.onTextChanged = { [weak self] newText in
            guard let self else { return }
            coordinator.parent.text = newText
            syncPlaceholderVisibility()
        }
        textView.onCommit = { [weak self] in
            guard let self else { return }
            coordinator.parent.onCommit()
            window?.makeFirstResponder(nil)
        }
        textView.onCancel = { [weak self] in
            guard let self else { return }
            coordinator.parent.onCancel()
            window?.makeFirstResponder(nil)
        }
        textView.onFocusChanged = { [weak self] isFocused in
            self?.coordinator.parent.isFocused = isFocused
        }
    }

    override func mouseDown(with event: NSEvent) {
        focusCaretAtEnd()
    }
}

final class RenameWrappingTextView: NSTextView {
    var onTextChanged: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChanged?(true)
        }
        return didBecomeFirstResponder
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChanged?(string)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        consumeRenameCommand(from: event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if consumeRenameCommand(from: event) {
            return
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        onCommit?()
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        onCommit?()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChanged?(false)
        }
        return didResignFirstResponder
    }

    @discardableResult
    func consumeRenameCommand(from event: NSEvent) -> Bool {
        guard event.type == .keyDown,
            let charactersIgnoringModifiers = event.charactersIgnoringModifiers
        else { return false }

        if RenameEditorKey.commitCharacters.contains(charactersIgnoringModifiers) {
            onCommit?()
            return true
        }

        if charactersIgnoringModifiers == RenameEditorKey.cancelCharacter {
            onCancel?()
            return true
        }

        return false
    }

}

private enum RenameEditorKey {
    static let commitCharacters: Set<String> = ["\r", "\u{3}"]
    static let cancelCharacter = "\u{1b}"
}
