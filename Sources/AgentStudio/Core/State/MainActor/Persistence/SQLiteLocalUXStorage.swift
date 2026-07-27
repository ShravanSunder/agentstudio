import Foundation

enum SQLiteLocalUXStorage {
    static let sidebarSurfaceRepos = "repos"
    static let sidebarSurfaceInbox = "inbox"
    static let recentWorkspaceTargetKindWorktree = "worktree"
    static let recentWorkspaceTargetKindCwdOnly = "cwdOnly"
    static let repoExplorerGroupingRepo = "repo"
    static let repoExplorerGroupingPane = "pane"
    static let repoExplorerGroupingTab = "tab"
    static let repoExplorerSortAscending = "ascending"
    static let repoExplorerSortDescending = "descending"
    static let repoExplorerVisibilityAll = "all"
    static let repoExplorerVisibilityFavoritesOnly = "favoritesOnly"
    static let inboxNotificationGroupingByTab = "byTab"
    static let inboxNotificationGroupingByRepo = "byRepo"
    static let inboxNotificationGroupingByPane = "byPane"
    static let inboxNotificationGroupingNone = "none"
    static let inboxNotificationSortNewestFirst = "newestFirst"
    static let inboxNotificationSortOldestFirst = "oldestFirst"
    static let inboxNotificationContentRollUpAlerts = "rollUpAlerts"
    static let inboxNotificationContentActivity = "activity"
    static let inboxNotificationContentAll = "all"
    static let inboxNotificationRowStateUnreadOnly = "unreadOnly"
    static let inboxNotificationRowStateAll = "all"

    private static let repoExplorerGroupingValues: Set<String> = [
        repoExplorerGroupingRepo,
        repoExplorerGroupingPane,
        repoExplorerGroupingTab,
    ]
    private static let repoExplorerSortValues: Set<String> = [
        repoExplorerSortAscending,
        repoExplorerSortDescending,
    ]
    private static let repoExplorerVisibilityValues: Set<String> = [
        repoExplorerVisibilityAll,
        repoExplorerVisibilityFavoritesOnly,
    ]
    private static let inboxNotificationGroupingValues: Set<String> = [
        inboxNotificationGroupingByTab,
        inboxNotificationGroupingByRepo,
        inboxNotificationGroupingByPane,
        inboxNotificationGroupingNone,
    ]
    private static let inboxNotificationSortValues: Set<String> = [
        inboxNotificationSortNewestFirst,
        inboxNotificationSortOldestFirst,
    ]
    private static let inboxNotificationContentValues: Set<String> = [
        inboxNotificationContentRollUpAlerts,
        inboxNotificationContentActivity,
        inboxNotificationContentAll,
    ]
    private static let inboxNotificationRowStateValues: Set<String> = [
        inboxNotificationRowStateUnreadOnly,
        inboxNotificationRowStateAll,
    ]

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

    static func sidebarSurface(from rawValue: String) -> SidebarSurface? {
        switch rawValue {
        case sidebarSurfaceRepos:
            .repos
        case sidebarSurfaceInbox:
            .inbox
        default:
            nil
        }
    }

    static func recentWorkspaceTargetKind(from rawValue: String) -> RecentWorkspaceTarget.Kind? {
        switch rawValue {
        case recentWorkspaceTargetKindWorktree:
            .worktree
        case recentWorkspaceTargetKindCwdOnly:
            .cwdOnly
        default:
            nil
        }
    }

    static func isValidRepoExplorerGrouping(_ rawValue: String) -> Bool {
        repoExplorerGroupingValues.contains(rawValue)
    }

    static func isValidRepoExplorerSort(_ rawValue: String) -> Bool {
        repoExplorerSortValues.contains(rawValue)
    }

    static func isValidRepoExplorerVisibility(_ rawValue: String) -> Bool {
        repoExplorerVisibilityValues.contains(rawValue)
    }

    static func isValidInboxNotificationGrouping(_ rawValue: String) -> Bool {
        inboxNotificationGroupingValues.contains(rawValue)
    }

    static func isValidInboxNotificationSort(_ rawValue: String) -> Bool {
        inboxNotificationSortValues.contains(rawValue)
    }

    static func isValidInboxNotificationContent(_ rawValue: String) -> Bool {
        inboxNotificationContentValues.contains(rawValue)
    }

    static func isValidInboxNotificationRowState(_ rawValue: String) -> Bool {
        inboxNotificationRowStateValues.contains(rawValue)
    }
}
