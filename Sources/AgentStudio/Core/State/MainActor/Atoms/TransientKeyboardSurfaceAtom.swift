import Foundation
import Observation

@MainActor
@Observable
final class TransientKeyboardSurfaceAtom {
    private(set) var surfaces: [TransientKeyboardSurface] = []

    var topAnySurface: TransientKeyboardSurface? {
        surfaces.last
    }

    func topSurface(for workspaceWindowId: UUID?) -> TransientKeyboardSurface? {
        guard let workspaceWindowId else { return nil }
        return surfaces.last { $0.workspaceWindowId == workspaceWindowId }
    }

    func present(
        _ kind: TransientKeyboardSurfaceKind,
        workspaceWindowId: UUID
    ) -> TransientKeyboardSurfaceToken {
        let surface = TransientKeyboardSurface(workspaceWindowId: workspaceWindowId, kind: kind)
        surfaces.append(surface)
        return surface.token
    }

    func dismiss(_ token: TransientKeyboardSurfaceToken) {
        surfaces.removeAll { $0.token == token }
    }

    func dismissAll() {
        surfaces.removeAll()
    }
}
