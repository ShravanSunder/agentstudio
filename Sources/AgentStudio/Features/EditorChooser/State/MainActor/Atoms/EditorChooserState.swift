import AgentStudioInfrastructure
import Foundation
import Observation

package struct EditorChooserSnapshot: Equatable {
    package var openForPaneId: UUID?
    package var bookmarkedEditorId: EditorTargetId?
}

@MainActor
@Observable
package final class EditorPreferenceAtom {
    package private(set) var bookmarkedEditorId: EditorTargetId?

    package init() {}

    package func setBookmarkedEditor(_ editorId: EditorTargetId?) {
        bookmarkedEditorId = editorId
    }

    package func hydrate(bookmarkedEditorId: EditorTargetId?) {
        self.bookmarkedEditorId = bookmarkedEditorId
    }

    package func clear() {
        bookmarkedEditorId = nil
    }
}

@MainActor
@Observable
package final class EditorChooserRuntimeAtom {
    package private(set) var openForPaneId: UUID?
    package private(set) var availableTargets: [ExternalEditorTarget] = []

    package init() {}

    package func setOpenEditorPane(_ paneId: UUID?) {
        openForPaneId = paneId
    }

    package func setAvailableTargets(_ targets: [ExternalEditorTarget]) {
        availableTargets = targets
    }

    package func clear() {
        openForPaneId = nil
        availableTargets = []
    }
}

@MainActor
package final class EditorChooserState {
    private let preferenceAtom: EditorPreferenceAtom
    private let runtimeAtom: EditorChooserRuntimeAtom

    package init(
        preferenceAtom: EditorPreferenceAtom = .init(),
        runtimeAtom: EditorChooserRuntimeAtom = .init()
    ) {
        self.preferenceAtom = preferenceAtom
        self.runtimeAtom = runtimeAtom
    }

    package var state: EditorChooserSnapshot {
        .init(
            openForPaneId: runtimeAtom.openForPaneId,
            bookmarkedEditorId: preferenceAtom.bookmarkedEditorId
        )
    }

    package var bookmarkedEditorId: EditorTargetId? {
        preferenceAtom.bookmarkedEditorId
    }

    package var openForPaneId: UUID? {
        runtimeAtom.openForPaneId
    }

    package var availableTargets: [ExternalEditorTarget] {
        runtimeAtom.availableTargets
    }

    package func setBookmarkedEditor(_ editorId: EditorTargetId?) {
        preferenceAtom.setBookmarkedEditor(editorId)
    }

    package func setOpenEditorPane(_ paneId: UUID?) {
        runtimeAtom.setOpenEditorPane(paneId)
    }

    package func setAvailableTargets(_ targets: [ExternalEditorTarget]) {
        runtimeAtom.setAvailableTargets(targets)
    }

    package func hydrate(bookmarkedEditorId: EditorTargetId?) {
        preferenceAtom.hydrate(bookmarkedEditorId: bookmarkedEditorId)
        runtimeAtom.clear()
    }

    package func clear() {
        preferenceAtom.clear()
        runtimeAtom.clear()
    }
}
