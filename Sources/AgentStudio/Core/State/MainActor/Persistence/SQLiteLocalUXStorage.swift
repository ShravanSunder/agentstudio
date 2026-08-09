import Foundation

package enum SQLiteLocalUXStorage {
    package static let sidebarSurfaceRepos = "repos"
    package static let sidebarSurfaceInbox = "inbox"
    package static let repoExplorerGroupingRepo = "repo"
    package static let repoExplorerGroupingPane = "pane"
    package static let repoExplorerGroupingTab = "tab"
    package static let repoExplorerSortAscending = "ascending"
    package static let repoExplorerSortDescending = "descending"
    package static let repoExplorerVisibilityAll = "all"
    package static let inboxNotificationGroupingByTab = "byTab"
    package static let inboxNotificationGroupingByRepo = "byRepo"
    package static let inboxNotificationGroupingByPane = "byPane"
    package static let inboxNotificationGroupingNone = "none"
    package static let inboxNotificationSortNewestFirst = "newestFirst"
    package static let inboxNotificationSortOldestFirst = "oldestFirst"
    package static let inboxNotificationContentRollUpAlerts = "rollUpAlerts"
    package static let inboxNotificationContentActivity = "activity"
    package static let inboxNotificationContentAll = "all"
    package static let inboxNotificationRowStateUnreadOnly = "unreadOnly"
    package static let inboxNotificationRowStateAll = "all"

    private static let repoExplorerGroupingValues: Set<String> = [
        repoExplorerGroupingRepo,
        repoExplorerGroupingPane,
        repoExplorerGroupingTab,
    ]
    private static let repoExplorerSortValues: Set<String> = [
        repoExplorerSortAscending,
        repoExplorerSortDescending,
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

    package static func storageValue(for surface: SidebarSurface) -> String {
        switch surface {
        case .repos:
            sidebarSurfaceRepos
        case .inbox:
            sidebarSurfaceInbox
        }
    }

    package static func sidebarSurface(from rawValue: String) -> SidebarSurface? {
        switch rawValue {
        case sidebarSurfaceRepos:
            .repos
        case sidebarSurfaceInbox:
            .inbox
        default:
            nil
        }
    }

    package static func isValidRepoExplorerGrouping(_ rawValue: String) -> Bool {
        repoExplorerGroupingValues.contains(rawValue)
    }

    package static func isValidRepoExplorerSort(_ rawValue: String) -> Bool {
        repoExplorerSortValues.contains(rawValue)
    }

    package static func isValidInboxNotificationGrouping(_ rawValue: String) -> Bool {
        inboxNotificationGroupingValues.contains(rawValue)
    }

    package static func isValidInboxNotificationSort(_ rawValue: String) -> Bool {
        inboxNotificationSortValues.contains(rawValue)
    }

    package static func isValidInboxNotificationContent(_ rawValue: String) -> Bool {
        inboxNotificationContentValues.contains(rawValue)
    }

    package static func isValidInboxNotificationRowState(_ rawValue: String) -> Bool {
        inboxNotificationRowStateValues.contains(rawValue)
    }
}
