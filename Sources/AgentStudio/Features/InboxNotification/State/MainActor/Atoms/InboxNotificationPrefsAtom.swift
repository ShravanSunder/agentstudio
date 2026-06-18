import Foundation
import Observation

/// User preferences for the notification inbox.
///
/// Persisted by `WorkspaceSettingsStore`; inbox history persistence imports
/// legacy preference fields only.
@MainActor
@Observable
final class InboxNotificationPrefsAtom {
    private(set) var grouping: InboxNotificationGrouping = .byTab
    private(set) var sort: InboxNotificationSort = .newestFirst
    private(set) var bellEnabled: Bool = false
    private(set) var globalInboxContentMode: InboxNotificationContentMode = .rollUpAlerts
    private(set) var globalInboxRowStateFilter: InboxNotificationRowStateFilter = .unreadOnly
    private(set) var paneInboxContentMode: InboxNotificationContentMode = .rollUpAlerts
    private(set) var paneInboxRowStateFilter: InboxNotificationRowStateFilter = .unreadOnly

    func setGrouping(_ grouping: InboxNotificationGrouping) {
        self.grouping = grouping
    }

    func setSort(_ sort: InboxNotificationSort) {
        self.sort = sort
    }

    func setBellEnabled(_ enabled: Bool) {
        self.bellEnabled = enabled
    }

    func setGlobalInboxContentMode(_ contentMode: InboxNotificationContentMode) {
        globalInboxContentMode = contentMode
    }

    func setGlobalInboxRowStateFilter(_ rowStateFilter: InboxNotificationRowStateFilter) {
        globalInboxRowStateFilter = rowStateFilter
    }

    func setPaneInboxContentMode(_ contentMode: InboxNotificationContentMode) {
        paneInboxContentMode = contentMode
    }

    func setPaneInboxRowStateFilter(_ rowStateFilter: InboxNotificationRowStateFilter) {
        paneInboxRowStateFilter = rowStateFilter
    }
}
