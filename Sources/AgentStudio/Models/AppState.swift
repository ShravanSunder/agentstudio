import Foundation
import CoreGraphics

/// Persistent application state
struct AppState: Codable {
    var projects: [Project]
    var openTabs: [OpenTab]
    var activeTabId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?

    init(
        projects: [Project] = [],
        openTabs: [OpenTab] = [],
        activeTabId: UUID? = nil,
        sidebarWidth: CGFloat = 250,
        windowFrame: CGRect? = nil
    ) {
        self.projects = projects
        self.openTabs = openTabs
        self.activeTabId = activeTabId
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
    }
}

/// An open terminal tab
struct OpenTab: Codable, Identifiable, Hashable {
    let id: UUID
    var worktreeId: UUID
    var projectId: UUID
    var order: Int

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        projectId: UUID,
        order: Int
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.projectId = projectId
        self.order = order
    }
}
