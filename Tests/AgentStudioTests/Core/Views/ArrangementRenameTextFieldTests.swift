import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ArrangementRenameTextFieldTests {
    @Test("text changes update the binding")
    func textChangesUpdateBinding() {
        let harness = ArrangementRenameTextFieldHarness()
        harness.field.stringValue = "Review"

        harness.coordinator.controlTextDidChange(
            Notification(name: NSText.didChangeNotification, object: harness.field))

        #expect(harness.text == "Review")
    }

    @Test("return commits and consumes the text-system command")
    func returnCommitsAndConsumesCommand() {
        let harness = ArrangementRenameTextFieldHarness()

        let consumed = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(consumed)
        #expect(harness.commitCount == 1)
        #expect(harness.cancelCount == 0)
    }

    @Test("escape cancels and consumes the text-system command")
    func escapeCancelsAndConsumesCommand() {
        let harness = ArrangementRenameTextFieldHarness()

        let consumed = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        )

        #expect(consumed)
        #expect(harness.cancelCount == 1)
        #expect(harness.commitCount == 0)
    }

    @Test("escape key events cancel even when characters are empty")
    func escapeKeyEventsCancelWhenCharactersAreEmpty() throws {
        let field = ArrangementRenameNSTextField()
        var cancelCount = 0
        field.onCancel = { cancelCount += 1 }
        let escapeEvent = try #require(
            makeKeyEvent(
                characters: "",
                charactersIgnoringModifiers: "",
                keyCode: 53
            )
        )

        let consumed = field.performKeyEquivalent(with: escapeEvent)

        #expect(consumed)
        #expect(cancelCount == 1)
    }

    @Test("arrow commands stay owned by the text editor")
    func arrowCommandsStayOwnedByTextEditor() {
        let harness = ArrangementRenameTextFieldHarness()

        let consumed = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.moveLeft(_:))
        )

        #expect(!consumed)
        #expect(harness.commitCount == 0)
        #expect(harness.cancelCount == 0)
    }

    @MainActor
    private final class ArrangementRenameTextFieldHarness {
        let state: ArrangementRenameTextFieldHarnessState
        let field: NSTextField
        let editor: NSTextView
        let coordinator: ArrangementRenameTextField.Coordinator

        var text: String { state.text }
        var commitCount: Int { state.commitCount }
        var cancelCount: Int { state.cancelCount }

        init() {
            let state = ArrangementRenameTextFieldHarnessState()
            self.state = state
            field = NSTextField()
            editor = NSTextView()

            let view = ArrangementRenameTextField(
                text: Binding(
                    get: { state.text },
                    set: { newText in state.text = newText }
                ),
                isFocused: .constant(false),
                font: .systemFont(ofSize: 12, weight: .semibold),
                onCommit: { state.commitCount += 1 },
                onCancel: { state.cancelCount += 1 }
            )
            coordinator = ArrangementRenameTextField.Coordinator(view)
        }
    }

    @MainActor
    private final class ArrangementRenameTextFieldHarnessState {
        var text = "Initial"
        var commitCount = 0
        var cancelCount = 0
    }
}
