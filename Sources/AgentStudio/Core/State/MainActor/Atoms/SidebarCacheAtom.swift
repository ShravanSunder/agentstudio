import Foundation
import Observation

/// Durable sidebar memory that can safely default without changing workspace meaning.
///
/// App-shell composition stays on `UIStateAtom`; workspace geometry stays on
/// `WorkspaceMetadataAtom`. Do not add focus, selected surface, collapsed state,
/// or width here.
@MainActor
@Observable
final class SidebarCacheAtom {
    private(set) var expandedGroups: Set<SidebarGroupKey> = []
    private(set) var checkoutColors: [SidebarCheckoutColorKey: String] = [:]
    private(set) var collapsedInboxGroups: Set<InboxNotificationGroupKey> = []

    func setGroupExpanded(_ key: SidebarGroupKey, isExpanded: Bool) {
        if isExpanded {
            expandedGroups.insert(key)
        } else {
            expandedGroups.remove(key)
        }
    }

    func setExpandedGroups(_ groups: Set<SidebarGroupKey>) {
        expandedGroups = groups
    }

    func setCheckoutColor(_ colorHex: String?, for key: SidebarCheckoutColorKey) {
        if let colorHex {
            checkoutColors[key] = colorHex
        } else {
            checkoutColors.removeValue(forKey: key)
        }
    }

    func setInboxGroupCollapsed(_ groupKey: InboxNotificationGroupKey, isCollapsed: Bool) {
        if isCollapsed {
            collapsedInboxGroups.insert(groupKey)
        } else {
            collapsedInboxGroups.remove(groupKey)
        }
    }

    func toggleInboxGroupCollapse(_ groupKey: InboxNotificationGroupKey) {
        setInboxGroupCollapsed(
            groupKey,
            isCollapsed: !collapsedInboxGroups.contains(groupKey)
        )
    }

    func isInboxGroupCollapsed(_ groupKey: InboxNotificationGroupKey) -> Bool {
        collapsedInboxGroups.contains(groupKey)
    }

    func hydrate(
        expandedGroups: Set<SidebarGroupKey>,
        checkoutColors: [SidebarCheckoutColorKey: String],
        collapsedInboxGroups: Set<InboxNotificationGroupKey>
    ) {
        self.expandedGroups = expandedGroups
        self.checkoutColors = checkoutColors
        self.collapsedInboxGroups = collapsedInboxGroups
    }

    func clear() {
        expandedGroups.removeAll(keepingCapacity: false)
        checkoutColors.removeAll(keepingCapacity: false)
        collapsedInboxGroups.removeAll(keepingCapacity: false)
    }
}
