import Foundation

@testable import AgentStudio

extension WorkspaceSQLiteSnapshot {
    static func emptyFixture(
        id: UUID = UUID(),
        name: String = "Workspace",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 2)
    ) -> Self {
        Self(
            id: id,
            name: name,
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            watchedPaths: [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
