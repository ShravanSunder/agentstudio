import SwiftUI

@MainActor
struct PaneNotePresentation {
    let present: (UUID) -> Void
    let editorContent: (_ paneId: UUID, _ submit: @escaping (String?) -> Void) -> AnyView

    static let disabled = Self(
        present: { _ in },
        editorContent: { _, _ in AnyView(EmptyView()) }
    )
}
