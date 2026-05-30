import Observation

@MainActor
@Observable
final class InboxSidebarMemoryAtom {
    private(set) var collapsedGroups: Set<InboxNotificationGroupKey> = []

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

@MainActor
@Observable
final class InboxSidebarRuntimeAtom {
    private(set) var pendingFilter: InboxFilter?

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
}

@MainActor
final class InboxSidebarState {
    private let memoryAtom: InboxSidebarMemoryAtom
    private let runtimeAtom: InboxSidebarRuntimeAtom

    init(
        memoryAtom: InboxSidebarMemoryAtom = .init(),
        runtimeAtom: InboxSidebarRuntimeAtom = .init()
    ) {
        self.memoryAtom = memoryAtom
        self.runtimeAtom = runtimeAtom
    }

    var pendingFilter: InboxFilter? {
        runtimeAtom.pendingFilter
    }

    var collapsedGroups: Set<InboxNotificationGroupKey> {
        memoryAtom.collapsedGroups
    }

    func setPendingFilter(_ filter: InboxFilter) {
        runtimeAtom.setPendingFilter(filter)
    }

    func peekPendingFilter() -> InboxFilter? {
        runtimeAtom.peekPendingFilter()
    }

    func consumePendingFilter() -> InboxFilter? {
        runtimeAtom.consumePendingFilter()
    }

    func clearPendingFilter() {
        runtimeAtom.clearPendingFilter()
    }

    func setGroupCollapsed(_ groupKey: InboxNotificationGroupKey, isCollapsed: Bool) {
        memoryAtom.setGroupCollapsed(groupKey, isCollapsed: isCollapsed)
    }

    func toggleGroupCollapse(_ groupKey: InboxNotificationGroupKey) {
        memoryAtom.toggleGroupCollapse(groupKey)
    }

    func isGroupCollapsed(_ groupKey: InboxNotificationGroupKey) -> Bool {
        memoryAtom.isGroupCollapsed(groupKey)
    }

    func hydrate(collapsedGroups: Set<InboxNotificationGroupKey>) {
        memoryAtom.hydrate(collapsedGroups: collapsedGroups)
        runtimeAtom.clearPendingFilter()
    }

    func clearCollapsedGroups() {
        memoryAtom.clearCollapsedGroups()
    }
}
