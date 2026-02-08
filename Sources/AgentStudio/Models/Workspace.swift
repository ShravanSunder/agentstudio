import Foundation
import CoreGraphics

// MARK: - OpenTab

/// An open terminal tab
struct OpenTab: Codable, Identifiable, Hashable {
    let id: UUID
    var worktreeId: UUID
    var repoId: UUID
    var order: Int
    var splitTreeData: Data?
    var activePaneId: UUID?

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        repoId: UUID,
        order: Int,
        splitTreeData: Data? = nil,
        activePaneId: UUID? = nil
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.repoId = repoId
        self.order = order
        self.splitTreeData = splitTreeData
        self.activePaneId = activePaneId
    }
}

// MARK: - Workspace

/// Top-level persistence unit for Agent Studio.
/// A workspace contains all repos, tabs, and settings for a single window.
struct Workspace: Codable, Identifiable {
    let id: UUID
    var name: String
    var repos: [Repo]
    var openTabs: [OpenTab]
    var activeTabId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Default Workspace",
        repos: [Repo] = [],
        openTabs: [OpenTab] = [],
        activeTabId: UUID? = nil,
        sidebarWidth: CGFloat = 250,
        windowFrame: CGRect? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repos = repos
        self.openTabs = openTabs
        self.activeTabId = activeTabId
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
