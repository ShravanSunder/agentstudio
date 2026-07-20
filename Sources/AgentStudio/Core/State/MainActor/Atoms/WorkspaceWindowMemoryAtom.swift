import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceWindowMemoryAtom {
    var sidebarWidth: CGFloat { storedSidebarWidth }
    var windowFrame: CGRect? { storedWindowFrame }

    private var storedSidebarWidth: CGFloat
    private var storedWindowFrame: CGRect?

    init(sidebarWidth: CGFloat = 250, windowFrame: CGRect? = nil) {
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

    func setSidebarWidth(_ sidebarWidth: CGFloat) {
        guard storedSidebarWidth != sidebarWidth else { return }
        storedSidebarWidth = sidebarWidth
    }

    func setWindowFrame(_ windowFrame: CGRect?) {
        guard storedWindowFrame != windowFrame else { return }
        storedWindowFrame = windowFrame
    }
}
