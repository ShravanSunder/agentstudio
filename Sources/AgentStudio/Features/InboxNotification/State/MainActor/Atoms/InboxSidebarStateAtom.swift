import Observation

@MainActor
@Observable
final class InboxSidebarStateAtom {
    private(set) var pendingFilter: InboxFilter?
    private(set) var collapsedGroups: Set<InboxNotificationGroupKey> = []

    func setPendingFilter(_ filter: InboxFilter) {
        pendingFilter = filter
    }

    func peekPendingFilter() -> InboxFilter? {
        pendingFilter
    }

    func consumePendingFilter() -> InboxFilter? {
        let filter = pendingFilter
        pendingFilter = nil
        return filter
    }

    func clearPendingFilter() {
        pendingFilter = nil
    }

    func setGroupCollapsed(_ groupKey: InboxNotificationGroupKey, isCollapsed: Bool) {
        if isCollapsed {
            collapsedGroups.insert(groupKey)
        } else {
            collapsedGroups.remove(groupKey)
        }
    }

    func toggleGroupCollapse(_ groupKey: InboxNotificationGroupKey) {
        setGroupCollapsed(
            groupKey,
            isCollapsed: !collapsedGroups.contains(groupKey)
        )
    }

    func isGroupCollapsed(_ groupKey: InboxNotificationGroupKey) -> Bool {
        collapsedGroups.contains(groupKey)
    }

    func hydrate(collapsedGroups: Set<InboxNotificationGroupKey>) {
        self.collapsedGroups = collapsedGroups
    }

    func clearCollapsedGroups() {
        collapsedGroups.removeAll(keepingCapacity: false)
    }
}
