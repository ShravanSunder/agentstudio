import Foundation
import Observation

@MainActor
@Observable
package final class WorkspaceWindowMemoryAtom {
    package var sidebarWidth: CGFloat { storedSidebarWidth }
    package var windowFrame: CGRect? { storedWindowFrame }

    private var storedSidebarWidth: CGFloat
    private var storedWindowFrame: CGRect?

    package init(sidebarWidth: CGFloat = 250, windowFrame: CGRect? = nil) {
        storedSidebarWidth = sidebarWidth
        storedWindowFrame = windowFrame
    }

    func replaceWindowMemory(
        sidebarWidth: CGFloat,
        windowFrame: CGRect?
    ) {
        storedSidebarWidth = sidebarWidth
        storedWindowFrame = windowFrame
    }

    package func setSidebarWidth(_ sidebarWidth: CGFloat) {
        guard storedSidebarWidth != sidebarWidth else { return }
        storedSidebarWidth = sidebarWidth
    }

    package func setWindowFrame(_ windowFrame: CGRect?) {
        guard storedWindowFrame != windowFrame else { return }
        storedWindowFrame = windowFrame
    }
}
