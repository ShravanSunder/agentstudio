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

    func replace(
        _ token: TransientKeyboardSurfaceToken,
        with kind: TransientKeyboardSurfaceKind,
        workspaceWindowId: UUID
    ) {
        guard let index = surfaces.firstIndex(where: { $0.token == token }) else {
            let surface = TransientKeyboardSurface(workspaceWindowId: workspaceWindowId, kind: kind)
            surfaces.append(surface)
            return
        }
        surfaces[index] = TransientKeyboardSurface(
            token: token,
            workspaceWindowId: workspaceWindowId,
            kind: kind
        )
    }

    func dismissAll() {
        surfaces.removeAll()
    }
}
