import CoreGraphics
import Foundation

/// Live workspace snapshot passed across the SQLite datastore boundary.
///
/// This is not the legacy JSON payload and not a SQLite row projection. It
/// carries the workspace-owned graph in the shape the SQLite bridge can
/// materialize into normalized core/local tables. Repository topology is
/// supplied separately by `RepositoryTopologySQLiteSnapshot`.
struct WorkspaceSQLiteSnapshot: Equatable, Sendable {
    var id: UUID
    var name: String
    var panes: [Pane]
    var tabs: [Tab]
    var activeTabId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String = "Default Workspace",
        panes: [Pane] = [],
        tabs: [Tab] = [],
        activeTabId: UUID? = nil,
        sidebarWidth: CGFloat = 250,
        windowFrame: CGRect? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.panes = panes
        self.tabs = tabs
        self.activeTabId = activeTabId
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func hasSameSQLiteRepresentation(as other: Self) -> Bool {
        id == other.id
            && name == other.name
            && panes == other.panes
            && tabs == other.tabs
            && activeTabId == other.activeTabId
            && sidebarWidth == other.sidebarWidth
            && windowFrame == other.windowFrame
            && createdAt.timeIntervalSince1970 == other.createdAt.timeIntervalSince1970
            && updatedAt.timeIntervalSince1970 == other.updatedAt.timeIntervalSince1970
    }
}
