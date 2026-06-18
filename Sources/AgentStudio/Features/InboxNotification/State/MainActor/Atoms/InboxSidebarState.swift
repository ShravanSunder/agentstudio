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
    private(set) var pendingDisplayOverride: InboxNotificationDisplayOverride?
    private(set) var shouldClearFilterOnNextRetarget = false
    private(set) var dismissalGeneration = 0
    private var retargetRequestGeneration = 0
    private var handledRetargetRequestGeneration = 0

    func setPendingFilter(_ filter: InboxFilter) {
        pendingFilter = filter
        retargetRequestGeneration += 1
    }

    func setPendingDisplayOverride(_ override: InboxNotificationDisplayOverride) {
        pendingDisplayOverride = override
        retargetRequestGeneration += 1
    }

    func requestFilterClearOnNextRetarget() {
        shouldClearFilterOnNextRetarget = true
        retargetRequestGeneration += 1
    }

    func peekPendingFilter() -> InboxFilter? {
        pendingFilter
    }

    func peekPendingDisplayOverride() -> InboxNotificationDisplayOverride? {
        pendingDisplayOverride
    }

    func consumePendingFilter() -> InboxFilter? {
        let filter = pendingFilter
        pendingFilter = nil
        return filter
    }

    func consumeFilterClearOnNextRetarget() -> Bool {
        let shouldClear = shouldClearFilterOnNextRetarget
        shouldClearFilterOnNextRetarget = false
        return shouldClear
    }

    func consumePendingDisplayOverride() -> InboxNotificationDisplayOverride? {
        let override = pendingDisplayOverride
        pendingDisplayOverride = nil
        return override
    }

    func clearPendingFilter() {
        pendingFilter = nil
        shouldClearFilterOnNextRetarget = false
    }

    func clearPendingDisplayOverride() {
        pendingDisplayOverride = nil
    }

    func hasUnhandledRetargetRequest() -> Bool {
        retargetRequestGeneration > handledRetargetRequestGeneration
    }

    func markRetargetRequestHandled() {
        handledRetargetRequestGeneration = retargetRequestGeneration
    }

    func markDismissed() {
        pendingFilter = nil
        pendingDisplayOverride = nil
        shouldClearFilterOnNextRetarget = false
        dismissalGeneration += 1
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

    var pendingDisplayOverride: InboxNotificationDisplayOverride? {
        runtimeAtom.pendingDisplayOverride
    }

    var collapsedGroups: Set<InboxNotificationGroupKey> {
        memoryAtom.collapsedGroups
    }

    func setPendingFilter(_ filter: InboxFilter) {
        runtimeAtom.setPendingFilter(filter)
    }

    func setPendingDisplayOverride(_ override: InboxNotificationDisplayOverride) {
        runtimeAtom.setPendingDisplayOverride(override)
    }

    func requestFilterClearOnNextRetarget() {
        runtimeAtom.requestFilterClearOnNextRetarget()
    }

    func peekPendingFilter() -> InboxFilter? {
        runtimeAtom.peekPendingFilter()
    }

    func peekPendingDisplayOverride() -> InboxNotificationDisplayOverride? {
        runtimeAtom.peekPendingDisplayOverride()
    }

    func consumePendingFilter() -> InboxFilter? {
        runtimeAtom.consumePendingFilter()
    }

    func consumeFilterClearOnNextRetarget() -> Bool {
        runtimeAtom.consumeFilterClearOnNextRetarget()
    }

    func consumePendingDisplayOverride() -> InboxNotificationDisplayOverride? {
        runtimeAtom.consumePendingDisplayOverride()
    }

    func clearPendingFilter() {
        runtimeAtom.clearPendingFilter()
    }

    func clearPendingDisplayOverride() {
        runtimeAtom.clearPendingDisplayOverride()
    }

    var dismissalGeneration: Int {
        runtimeAtom.dismissalGeneration
    }

    func hasUnhandledRetargetRequest() -> Bool {
        runtimeAtom.hasUnhandledRetargetRequest()
    }

    func markRetargetRequestHandled() {
        runtimeAtom.markRetargetRequestHandled()
    }

    func markDismissed() {
        runtimeAtom.markDismissed()
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
        runtimeAtom.clearPendingDisplayOverride()
    }

    func clearCollapsedGroups() {
        memoryAtom.clearCollapsedGroups()
    }
}
