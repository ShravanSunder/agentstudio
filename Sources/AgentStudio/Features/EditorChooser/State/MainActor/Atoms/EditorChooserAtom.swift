import Foundation
import Observation

struct EditorChooserState: Equatable {
    var openForPaneId: UUID?
    var bookmarkedEditorId: EditorTargetId?
}

@MainActor
@Observable
final class EditorChooserAtom {
    private(set) var state: EditorChooserState = .init()
    private(set) var availableTargets: [ExternalEditorTarget] = []

    func setBookmarkedEditor(_ editorId: EditorTargetId?) {
        state.bookmarkedEditorId = editorId
    }

    func setOpenEditorPane(_ paneId: UUID?) {
        state.openForPaneId = paneId
    }

    func setAvailableTargets(_ targets: [ExternalEditorTarget]) {
        availableTargets = targets
    }

    func hydrate(bookmarkedEditorId: EditorTargetId?) {
        state = .init(openForPaneId: nil, bookmarkedEditorId: bookmarkedEditorId)
        availableTargets = []
    }

    func clear() {
        state = .init()
        availableTargets = []
    }
}
