import AppKit
import GhosttyKit

@MainActor
protocol TerminalSurfaceActionPerforming: AnyObject {
    @discardableResult
    func performBindingAction(_ action: String) -> Bool
}

extension Ghostty.SurfaceView: TerminalSurfaceActionPerforming {
    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }
}
