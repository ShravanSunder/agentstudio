import Testing

@testable import AgentStudio

@Suite
struct PaneNotePopoverTests {
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
