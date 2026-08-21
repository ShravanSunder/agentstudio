import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudio

@Suite
struct PaneNotePopoverTests {
    @Test("toolbar-anchored presentation preserves the requested pane identity until consumed")
    @MainActor
    func toolbarAnchoredPresentationRoutesByPaneIdentity() throws {
        let presentation = PaneNotePresentation.toolbarAnchored()
        let paneId = UUIDv7.generate()

        presentation.present(paneId)

        let request = try #require(presentation.pendingRequest())
        #expect(request.paneId == paneId)
        presentation.clearRequest(request)
        #expect(presentation.pendingRequest() == nil)
    }

    @Test("popover uses sixty percent of the pane with existing dimensions as minimums")
    @MainActor
    func preferredSizeUsesPaneRatioAndMinimums() {
        #expect(PaneNotePopover.preferredSize(owningPaneSize: nil) == CGSize(width: 380, height: 220))
        #expect(
            PaneNotePopover.preferredSize(owningPaneSize: CGSize(width: 1000, height: 800))
                == CGSize(width: 600, height: 480)
        )
    }

    @Test("multiline note Return inserts a newline while rename Return commits")
    @MainActor
    func returnBehaviorRespectsMultilineMode() {
        let noteView = RenameWrappingTextView(frame: .zero)
        noteView.allowsNewlines = true
        noteView.string = "First"
        noteView.setSelectedRange(NSRange(location: noteView.string.utf16.count, length: 0))
        var noteCommitCount = 0
        noteView.onCommit = { noteCommitCount += 1 }

        noteView.insertNewline(nil)

        #expect(noteView.string == "First\n")
        #expect(noteCommitCount == 0)

        let renameView = RenameWrappingTextView(frame: .zero)
        var renameCommitCount = 0
        renameView.onCommit = { renameCommitCount += 1 }

        renameView.insertNewline(nil)

        #expect(renameCommitCount == 1)
    }

    @Test("cancel never commits edited text")
    func cancelNeverCommitsEditedText() {
        var draft = PaneNotePopoverDraft(currentNote: "Before")
        var commits: [String?] = []
        var cancelCount = 0

        draft.noteText = "After"
        draft.cancel(onCancel: { cancelCount += 1 })
        draft.implicitDismiss { commits.append($0) }

        #expect(cancelCount == 1)
        #expect(commits.isEmpty)
    }

    @Test("explicit commit submits the edited text once")
    func explicitCommitSubmitsEditedTextOnce() {
        var draft = PaneNotePopoverDraft(currentNote: "Before")
        var commits: [String?] = []

        draft.noteText = "After"
        draft.commit { commits.append($0) }
        draft.implicitDismiss { commits.append($0) }

        #expect(commits == ["After"])
    }

    @Test("implicit outside dismiss commits changed text")
    func implicitOutsideDismissCommitsChangedText() {
        var draft = PaneNotePopoverDraft(currentNote: "Before")
        var commits: [String?] = []

        draft.noteText = "After"
        draft.implicitDismiss { commits.append($0) }

        #expect(commits == ["After"])
    }

    @Test("implicit outside dismiss ignores unchanged text")
    func implicitOutsideDismissIgnoresUnchangedText() {
        var draft = PaneNotePopoverDraft(currentNote: "Before")
        var commits: [String?] = []

        draft.noteText = " Before "
        draft.implicitDismiss { commits.append($0) }

        #expect(commits.isEmpty)
    }

    @Test("blank commit is forwarded for atom normalization")
    func blankCommitIsForwardedForAtomNormalization() {
        var draft = PaneNotePopoverDraft(currentNote: "Before")
        var commits: [String?] = []

        draft.noteText = ""
        draft.commit { commits.append($0) }

        #expect(commits == [""])
    }
}
