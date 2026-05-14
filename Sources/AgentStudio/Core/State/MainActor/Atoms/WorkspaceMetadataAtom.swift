import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceMetadataAtom {
    private(set) var workspaceId = UUID()
    private(set) var workspaceName: String = "Default Workspace"
    private(set) var createdAt = Date()
    private(set) var sidebarWidth: CGFloat = 250
    private(set) var windowFrame: CGRect?

    func hydrate(
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date,
        sidebarWidth: CGFloat,
        windowFrame: CGRect?
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.createdAt = createdAt
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
    }

    func setWorkspaceName(_ workspaceName: String) {
        guard self.workspaceName != workspaceName else { return }
        self.workspaceName = workspaceName
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
