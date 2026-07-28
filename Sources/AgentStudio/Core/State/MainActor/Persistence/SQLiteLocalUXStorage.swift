import Foundation

enum SQLiteLocalUXStorage {
    static let sidebarSurfaceRepos = "repos"
    static let sidebarSurfaceInbox = "inbox"

    static func storageValue(for surface: SidebarSurface) -> String {
        switch surface {
        case .repos:
            sidebarSurfaceRepos
        case .inbox:
            sidebarSurfaceInbox
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

    static func storageValue(for value: RepoExplorerGroupingMode) -> String {
        switch value {
        case .repo: "repo"
        case .pane: "pane"
        case .tab: "tab"
        }
    }

    static func storageValue(for value: RepoExplorerSortOrder) -> String {
        switch value {
        case .ascending: "ascending"
        case .descending: "descending"
        }
    }

    static func storageValue(for value: RepoExplorerVisibilityMode) -> String {
        switch value {
        case .all: "all"
        case .favoritesOnly: "favoritesOnly"
        }
    }

    static func storageValue(for value: InboxNotificationGrouping) -> String {
        switch value {
        case .byTab: "byTab"
        case .byRepo: "byRepo"
        case .byPane: "byPane"
        case .none: "none"
        }
    }

    static func storageValue(for value: InboxNotificationSort) -> String {
        switch value {
        case .newestFirst: "newestFirst"
        case .oldestFirst: "oldestFirst"
        }
    }

    static func storageValue(for value: InboxNotificationContentMode) -> String {
        switch value {
        case .rollUpAlerts: "rollUpAlerts"
        case .activity: "activity"
        case .all: "all"
        }
    }

    static func storageValue(for value: InboxNotificationRowStateFilter) -> String {
        switch value {
        case .unreadOnly: "unreadOnly"
        case .all: "all"
        }
    }
}
