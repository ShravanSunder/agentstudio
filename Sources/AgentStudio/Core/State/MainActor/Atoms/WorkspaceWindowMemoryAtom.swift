import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceWindowMemoryAtom {
    private(set) var sidebarWidth: CGFloat = 250
    private(set) var windowFrame: CGRect?

    func hydrate(
        sidebarWidth: CGFloat,
        windowFrame: CGRect?
    ) {
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
    }

    func setSidebarWidth(_ sidebarWidth: CGFloat) {
        guard self.sidebarWidth != sidebarWidth else { return }
        self.sidebarWidth = sidebarWidth
    }

    func setWindowFrame(_ windowFrame: CGRect?) {
        guard self.windowFrame != windowFrame else { return }
        self.windowFrame = windowFrame
    }
}
