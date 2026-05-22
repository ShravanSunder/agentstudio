import Foundation

struct TransientKeyboardSurfaceToken: Equatable, Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum TransientKeyboardSurfaceKind: Equatable, Sendable {
    case tabRename(tabId: UUID)
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
