import Foundation

extension SurfaceManager {
    /// Ends the accumulator lifetime before a surface can be reused or destroyed.
    func detachTerminalLocalActions(surfaceID: UUID, paneID: UUID?) {
        if let paneID {
            Ghostty.ActionRouter.closeLocalActions(surfaceID: surfaceID, paneID: paneID)
        } else {
            Ghostty.ActionRouter.retireLocalActions(for: surfaceID)
        }
    }
}
