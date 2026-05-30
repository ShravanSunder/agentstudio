import Foundation

enum SQLiteLocalUXStorage {
    static let sidebarSurfaceRepos = "repos"
    static let sidebarSurfaceInbox = "inbox"
    static let recentWorkspaceTargetKindWorktree = "worktree"
    static let recentWorkspaceTargetKindCwdOnly = "cwdOnly"

    static let sidebarSurfaceSQLValues = sqlValueList([sidebarSurfaceRepos, sidebarSurfaceInbox])
    static let recentWorkspaceTargetKindSQLValues = sqlValueList([
        recentWorkspaceTargetKindWorktree,
        recentWorkspaceTargetKindCwdOnly,
    ])

    static func storageValue(for surface: SidebarSurface) -> String {
        switch surface {
        case .repos:
            sidebarSurfaceRepos
        case .inbox:
            sidebarSurfaceInbox
        }
    }

    static func storageValue(for kind: RecentWorkspaceTarget.Kind) -> String {
        switch kind {
        case .worktree:
            recentWorkspaceTargetKindWorktree
        case .cwdOnly:
            recentWorkspaceTargetKindCwdOnly
        }
    }

    private static func sqlValueList(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }
}
