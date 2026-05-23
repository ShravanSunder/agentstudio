import Foundation
import Observation

struct CommandBarSurface: Equatable, Sendable {
    let workspaceWindowId: UUID
    let scope: CommandBarScope
}

@MainActor
@Observable
final class CommandBarSurfaceAtom {
    private(set) var activeSurface: CommandBarSurface?

    var activeScope: CommandBarScope? {
        activeSurface?.scope
    }

    var isActive: Bool {
        activeSurface != nil
    }

    func activeScope(for workspaceWindowId: UUID?) -> CommandBarScope? {
        guard let workspaceWindowId else { return nil }
        guard activeSurface?.workspaceWindowId == workspaceWindowId else { return nil }
        return activeSurface?.scope
    }

    func present(scope: CommandBarScope, workspaceWindowId: UUID) {
        activeSurface = CommandBarSurface(workspaceWindowId: workspaceWindowId, scope: scope)
    }

    func dismiss(workspaceWindowId: UUID? = nil) {
        guard let workspaceWindowId else {
            activeSurface = nil
            return
        }
        guard activeSurface?.workspaceWindowId == workspaceWindowId else { return }
        activeSurface = nil
    }
}
