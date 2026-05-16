import Foundation
import Observation

/// User preferences for the notification inbox.
///
/// Persisted alongside `InboxNotificationAtom` by `InboxNotificationStore`.
@MainActor
@Observable
final class InboxNotificationPrefsAtom {
    private(set) var grouping: InboxNotificationGrouping = .byTab
    private(set) var sort: InboxNotificationSort = .newestFirst
    private(set) var bellEnabled: Bool = false

    func setGrouping(_ grouping: InboxNotificationGrouping) {
        self.grouping = grouping
    }

    func setSort(_ sort: InboxNotificationSort) {
        self.sort = sort
    }

    func setBellEnabled(_ enabled: Bool) {
        self.bellEnabled = enabled
    }
}
