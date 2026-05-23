import Foundation

struct TransientKeyboardSurfaceToken: Equatable, Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum TransientKeyboardSurfaceKind: Equatable, Sendable {
    case tabRename(tabId: UUID)
    case arrangementPanel(tabId: UUID)
    case arrangementRename(tabId: UUID, arrangementId: UUID)
    case paneInbox(parentPaneId: UUID)
    case editorChooser(paneId: UUID)
}

struct TransientKeyboardSurface: Equatable, Identifiable, Sendable {
    let token: TransientKeyboardSurfaceToken
    let workspaceWindowId: UUID
    let kind: TransientKeyboardSurfaceKind

    var id: TransientKeyboardSurfaceToken { token }

    init(
        token: TransientKeyboardSurfaceToken = TransientKeyboardSurfaceToken(),
        workspaceWindowId: UUID,
        kind: TransientKeyboardSurfaceKind
    ) {
        self.token = token
        self.workspaceWindowId = workspaceWindowId
        self.kind = kind
    }
}
