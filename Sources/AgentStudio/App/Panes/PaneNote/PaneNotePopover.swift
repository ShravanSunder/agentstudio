import SwiftUI

struct PaneNotePopoverDraft {
    private(set) var currentNote: String?
    var noteText: String
    private var didComplete = false

    init(currentNote: String?) {
        self.currentNote = currentNote
        self.noteText = currentNote ?? ""
    }

    mutating func reset(currentNote: String?) {
        self.currentNote = currentNote
        noteText = currentNote ?? ""
        didComplete = false
    }

    mutating func commit(_ onCommit: (String?) -> Void) {
        guard !didComplete else { return }
        didComplete = true
        onCommit(noteText)
    }

    mutating func cancel(onCancel: () -> Void) {
        guard !didComplete else { return }
        didComplete = true
        onCancel()
    }

    mutating func implicitDismiss(_ onCommit: (String?) -> Void) {
        guard !didComplete else { return }
        guard Self.normalized(noteText) != Self.normalized(currentNote) else { return }
        didComplete = true
        onCommit(noteText)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PaneNotePopover: View {
    let currentNote: String?
    let onCommit: (String?) -> Void
    let onCancel: () -> Void

    @State private var draft: PaneNotePopoverDraft
    @State private var isNoteFieldFocused = false

    init(
        currentNote: String?,
        onCommit: @escaping (String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.currentNote = currentNote
        self.onCommit = onCommit
        self.onCancel = onCancel
        _draft = State(initialValue: PaneNotePopoverDraft(currentNote: currentNote))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pane Note")
                .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                .foregroundStyle(.secondary)

            RenameWrappingTextField(
                placeholder: "Note",
                text: $draft.noteText,
                isFocused: $isNoteFieldFocused,
                onCommit: commitNote,
                onCancel: cancelNote
            )
            .frame(minHeight: 96)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(AppStyles.General.Fill.subtle))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isNoteFieldFocused ? Color.accentColor : Color.white.opacity(0.12),
                        lineWidth: isNoteFieldFocused ? 2 : 1
                    )
            }

            HStack {
                Spacer()

                Button(LocalActionSpec.cancel.actionSpec.label, role: .cancel) {
                    cancelNote()
                }

                Button("Save", action: commitNote)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            draft.reset(currentNote: currentNote)
        }
        .onDisappear {
            draft.implicitDismiss(onCommit)
        }
    }

    private func commitNote() {
        draft.commit(onCommit)
    }

    private func cancelNote() {
        draft.cancel(onCancel: onCancel)
    }
}
