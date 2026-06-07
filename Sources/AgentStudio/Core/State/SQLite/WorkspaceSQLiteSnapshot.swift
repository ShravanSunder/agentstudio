import CoreGraphics
import Foundation

/// Live workspace snapshot passed across the SQLite datastore boundary.
///
/// This is not the legacy JSON payload and not a SQLite row projection. It
/// carries the current workspace graph in the shape the SQLite bridge can
/// materialize into normalized core/local tables.
struct WorkspaceSQLiteSnapshot: Equatable, Sendable {
    var id: UUID
    var name: String
    var repos: [CanonicalRepo]
    var worktrees: [CanonicalWorktree]
    var unavailableRepoIds: Set<UUID>
    var panes: [Pane]
    var tabs: [Tab]
    var activeTabId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
    var watchedPaths: [WatchedPath]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Default Workspace",
        repos: [CanonicalRepo] = [],
        worktrees: [CanonicalWorktree] = [],
        unavailableRepoIds: Set<UUID> = [],
        panes: [Pane] = [],
        tabs: [Tab] = [],
        activeTabId: UUID? = nil,
        sidebarWidth: CGFloat = 250,
        windowFrame: CGRect? = nil,
        watchedPaths: [WatchedPath] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repos = repos
        self.worktrees = worktrees
        self.unavailableRepoIds = unavailableRepoIds
        self.panes = panes
        self.tabs = tabs
        self.activeTabId = activeTabId
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
        self.watchedPaths = watchedPaths
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
