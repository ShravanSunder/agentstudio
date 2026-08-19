import AgentStudioInfrastructure
import SwiftUI

@MainActor
@Observable
final class PaneNotePresentationState {
    struct Request: Equatable, Identifiable {
        let id: UUID
        let paneId: UUID
    }

    private(set) var pendingRequest: Request?

    func requestPresentation(for paneId: UUID) {
        pendingRequest = Request(id: UUIDv7.generate(), paneId: paneId)
    }

    func clear(_ request: Request) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}

@MainActor
struct PaneNotePresentation {
    let present: (UUID) -> Void
    let editorContent: (_ paneId: UUID, _ submit: @escaping (String?) -> Void) -> AnyView
    let pendingRequest: () -> PaneNotePresentationState.Request?
    let clearRequest: (PaneNotePresentationState.Request) -> Void

    init(
        present: @escaping (UUID) -> Void,
        editorContent: @escaping (_ paneId: UUID, _ submit: @escaping (String?) -> Void) -> AnyView,
        pendingRequest: @escaping () -> PaneNotePresentationState.Request? = { nil },
        clearRequest: @escaping (PaneNotePresentationState.Request) -> Void = { _ in }
    ) {
        self.present = present
        self.editorContent = editorContent
        self.pendingRequest = pendingRequest
        self.clearRequest = clearRequest
    }

    static func toolbarAnchored() -> Self {
        let state = PaneNotePresentationState()
        return Self(
            present: { paneId in state.requestPresentation(for: paneId) },
            editorContent: { _, _ in AnyView(EmptyView()) },
            pendingRequest: { state.pendingRequest },
            clearRequest: { request in state.clear(request) }
        )
    }

    static let disabled = Self(
        present: { _ in },
        editorContent: { _, _ in AnyView(EmptyView()) }
    )
}
