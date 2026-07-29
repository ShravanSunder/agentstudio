import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation
import Observation

/// User preferences for the notification inbox.
///
/// Persisted by `WorkspaceSettingsStore`; inbox history persistence imports
/// legacy preference fields only.
@MainActor
@Observable
package final class InboxNotificationPrefsAtom {
    package private(set) var grouping: InboxNotificationGrouping = .byTab
    package private(set) var sort: InboxNotificationSort = .newestFirst
    package private(set) var bellEnabled: Bool = false
    package private(set) var globalInboxContentMode: InboxNotificationContentMode = .rollUpAlerts
    package private(set) var globalInboxRowStateFilter: InboxNotificationRowStateFilter = .unreadOnly
    package private(set) var paneInboxContentMode: InboxNotificationContentMode = .rollUpAlerts
    package private(set) var paneInboxRowStateFilter: InboxNotificationRowStateFilter = .unreadOnly

    package init() {}

    package func setGrouping(_ grouping: InboxNotificationGrouping) {
        self.grouping = grouping
    }

    package func setSort(_ sort: InboxNotificationSort) {
        self.sort = sort
    }

    package func setBellEnabled(_ enabled: Bool) {
        self.bellEnabled = enabled
    }

    package func setGlobalInboxContentMode(_ contentMode: InboxNotificationContentMode) {
        globalInboxContentMode = contentMode
    }

    package func setGlobalInboxRowStateFilter(_ rowStateFilter: InboxNotificationRowStateFilter) {
        globalInboxRowStateFilter = rowStateFilter
    }

    package func setPaneInboxContentMode(_ contentMode: InboxNotificationContentMode) {
        paneInboxContentMode = contentMode
    }

    package func setPaneInboxRowStateFilter(_ rowStateFilter: InboxNotificationRowStateFilter) {
        paneInboxRowStateFilter = rowStateFilter
    }
}
