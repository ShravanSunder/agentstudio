import AgentStudioInfrastructure
import AppKit
import Foundation
import GhosttyKit

extension Ghostty.SurfaceView {
    func handleCloseRequested() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let processExited = self.processExited
            RestoreTrace.log(
                "Ghostty.SurfaceView.closeRequest processExited=\(processExited) mainThread=\(Thread.isMainThread)"
            )
            self.onCloseRequested?(processExited)
        }
    }
}
