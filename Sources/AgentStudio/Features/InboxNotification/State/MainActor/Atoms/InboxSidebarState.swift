import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Observation

@MainActor
@Observable
package final class InboxSidebarMemoryAtom {
    package private(set) var collapsedGroups: Set<InboxNotificationGroupKey> = []

    package init() {}

    package func setGroupCollapsed(_ groupKey: InboxNotificationGroupKey, isCollapsed: Bool) {
        if isCollapsed {
            collapsedGroups.insert(groupKey)
        } else {
            collapsedGroups.remove(groupKey)
        }
    }

    package func toggleGroupCollapse(_ groupKey: InboxNotificationGroupKey) {
        setGroupCollapsed(
            groupKey,
            isCollapsed: !collapsedGroups.contains(groupKey)
        )
    }

    package func isGroupCollapsed(_ groupKey: InboxNotificationGroupKey) -> Bool {
        collapsedGroups.contains(groupKey)
    }

    package func hydrate(collapsedGroups: Set<InboxNotificationGroupKey>) {
        self.collapsedGroups = collapsedGroups
    }

    package func clearCollapsedGroups() {
        collapsedGroups.removeAll(keepingCapacity: false)
    }
}

@MainActor
@Observable
package final class InboxSidebarRuntimeAtom {
    package private(set) var pendingFilter: InboxFilter?
    package private(set) var pendingDisplayOverride: InboxNotificationDisplayOverride?
    package private(set) var shouldClearFilterOnNextRetarget = false
    package private(set) var dismissalGeneration = 0
    private var retargetRequestGeneration = 0
    private var handledRetargetRequestGeneration = 0

    package init() {}

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
package final class InboxSidebarState {
    private let memoryAtom: InboxSidebarMemoryAtom
    private let runtimeAtom: InboxSidebarRuntimeAtom

    package init(
        memoryAtom: InboxSidebarMemoryAtom = .init(),
        runtimeAtom: InboxSidebarRuntimeAtom = .init()
    ) {
        self.memoryAtom = memoryAtom
        self.runtimeAtom = runtimeAtom
    }

    package var pendingFilter: InboxFilter? {
        runtimeAtom.pendingFilter
    }

    package var pendingDisplayOverride: InboxNotificationDisplayOverride? {
        runtimeAtom.pendingDisplayOverride
    }

    package var collapsedGroups: Set<InboxNotificationGroupKey> {
        memoryAtom.collapsedGroups
    }

    package func setPendingFilter(_ filter: InboxFilter) {
        runtimeAtom.setPendingFilter(filter)
    }

    package func setPendingDisplayOverride(_ override: InboxNotificationDisplayOverride) {
        runtimeAtom.setPendingDisplayOverride(override)
    }

    package func requestFilterClearOnNextRetarget() {
        runtimeAtom.requestFilterClearOnNextRetarget()
    }

    package func peekPendingFilter() -> InboxFilter? {
        runtimeAtom.peekPendingFilter()
    }

    package func peekPendingDisplayOverride() -> InboxNotificationDisplayOverride? {
        runtimeAtom.peekPendingDisplayOverride()
    }

    package func consumePendingFilter() -> InboxFilter? {
        runtimeAtom.consumePendingFilter()
    }

    package func consumeFilterClearOnNextRetarget() -> Bool {
        runtimeAtom.consumeFilterClearOnNextRetarget()
    }

    package func consumePendingDisplayOverride() -> InboxNotificationDisplayOverride? {
        runtimeAtom.consumePendingDisplayOverride()
    }

    package func clearPendingFilter() {
        runtimeAtom.clearPendingFilter()
    }

    package func clearPendingDisplayOverride() {
        runtimeAtom.clearPendingDisplayOverride()
    }

    package var dismissalGeneration: Int {
        runtimeAtom.dismissalGeneration
    }

    package func hasUnhandledRetargetRequest() -> Bool {
        runtimeAtom.hasUnhandledRetargetRequest()
    }

    package func markRetargetRequestHandled() {
        runtimeAtom.markRetargetRequestHandled()
    }

    package func markDismissed() {
        runtimeAtom.markDismissed()
    }

    package func setGroupCollapsed(_ groupKey: InboxNotificationGroupKey, isCollapsed: Bool) {
        memoryAtom.setGroupCollapsed(groupKey, isCollapsed: isCollapsed)
    }

    package func toggleGroupCollapse(_ groupKey: InboxNotificationGroupKey) {
        memoryAtom.toggleGroupCollapse(groupKey)
    }

    package func isGroupCollapsed(_ groupKey: InboxNotificationGroupKey) -> Bool {
        memoryAtom.isGroupCollapsed(groupKey)
    }

    package func hydrate(collapsedGroups: Set<InboxNotificationGroupKey>) {
        memoryAtom.hydrate(collapsedGroups: collapsedGroups)
        runtimeAtom.clearPendingFilter()
        runtimeAtom.clearPendingDisplayOverride()
    }

    package func clearCollapsedGroups() {
        memoryAtom.clearCollapsedGroups()
    }
}
