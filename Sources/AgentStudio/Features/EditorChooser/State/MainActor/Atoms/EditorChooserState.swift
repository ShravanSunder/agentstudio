import Foundation
import Observation

struct EditorChooserSnapshot: Equatable {
    var openForPaneId: UUID?
    var bookmarkedEditorId: EditorTargetId?
}

@MainActor
@Observable
final class EditorPreferenceAtom {
    private(set) var bookmarkedEditorId: EditorTargetId?

    func setBookmarkedEditor(_ editorId: EditorTargetId?) {
        bookmarkedEditorId = editorId
    }

    func hydrate(bookmarkedEditorId: EditorTargetId?) {
        self.bookmarkedEditorId = bookmarkedEditorId
    }

    func clear() {
        bookmarkedEditorId = nil
    }
}

@MainActor
@Observable
final class EditorChooserRuntimeAtom {
    private(set) var openForPaneId: UUID?
    private(set) var availableTargets: [ExternalEditorTarget] = []

    func setOpenEditorPane(_ paneId: UUID?) {
        openForPaneId = paneId
    }

    func setAvailableTargets(_ targets: [ExternalEditorTarget]) {
        availableTargets = targets
    }

    func clear() {
        openForPaneId = nil
        availableTargets = []
    }
}

@MainActor
final class EditorChooserState {
    private let preferenceAtom: EditorPreferenceAtom
    private let runtimeAtom: EditorChooserRuntimeAtom

    init(
        preferenceAtom: EditorPreferenceAtom = .init(),
        runtimeAtom: EditorChooserRuntimeAtom = .init()
    ) {
        self.preferenceAtom = preferenceAtom
        self.runtimeAtom = runtimeAtom
    }

    var state: EditorChooserSnapshot {
        .init(
            openForPaneId: runtimeAtom.openForPaneId,
            bookmarkedEditorId: preferenceAtom.bookmarkedEditorId
        )
    }

    var bookmarkedEditorId: EditorTargetId? {
        preferenceAtom.bookmarkedEditorId
    }

    var openForPaneId: UUID? {
        runtimeAtom.openForPaneId
    }

    var availableTargets: [ExternalEditorTarget] {
        runtimeAtom.availableTargets
    }

    func setBookmarkedEditor(_ editorId: EditorTargetId?) {
        preferenceAtom.setBookmarkedEditor(editorId)
    }

    func setOpenEditorPane(_ paneId: UUID?) {
        runtimeAtom.setOpenEditorPane(paneId)
    }

    func setAvailableTargets(_ targets: [ExternalEditorTarget]) {
        runtimeAtom.setAvailableTargets(targets)
    }

    func hydrate(bookmarkedEditorId: EditorTargetId?) {
        preferenceAtom.hydrate(bookmarkedEditorId: bookmarkedEditorId)
        runtimeAtom.clear()
    }

    func clear() {
        preferenceAtom.clear()
        runtimeAtom.clear()
    }
}
