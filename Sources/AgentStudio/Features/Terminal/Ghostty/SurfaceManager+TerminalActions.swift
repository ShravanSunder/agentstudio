import Foundation
import GhosttyKit

extension SurfaceManager {
    func scrollToBottom(forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        performBindingAction(.scrollToBottom, forPaneId: paneId)
    }

    func scrollPageUp(forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        performBindingAction(.scrollPageUp, forPaneId: paneId)
    }

    func jumpToPrompt(delta: Int, forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        performBindingAction(.jumpToPrompt(delta), forPaneId: paneId)
    }

    private func performBindingAction(
        _ terminalAction: TerminalSurfaceAction,
        forPaneId paneId: UUID
    ) -> Result<Void, SurfaceError> {
        guard let surfaceId = surfaceId(forPaneId: paneId) else {
            return .failure(.surfaceNotFound)
        }

        let action = terminalAction.bindingActionString
        let didPerform = withSurface(surfaceId) { surface in
            action.withCString { ptr in
                ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
            }
        }

        switch didPerform {
        case .success(true):
            return .success(())
        case .success(false):
            return .failure(.operationFailed("Ghostty rejected \(action) binding action"))
        case .failure(let error):
            return .failure(error)
        }
    }
}
