import Foundation
import Observation

/// Durable sidebar memory that can safely default without changing workspace meaning.
///
/// App-shell composition stays on `WorkspaceSidebarState`; workspace geometry stays on
/// `WorkspaceWindowMemoryAtom`. Do not add focus, selected surface, collapsed state,
/// or width here.
@MainActor
@Observable
final class SidebarCacheAtom {
    private(set) var expandedGroups: Set<SidebarGroupKey> = []
    private(set) var checkoutColors: [SidebarCheckoutColorKey: String] = [:]

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

    func hydrate(
        expandedGroups: Set<SidebarGroupKey>,
        checkoutColors: [SidebarCheckoutColorKey: String]
    ) {
        self.expandedGroups = expandedGroups
        self.checkoutColors = checkoutColors
    }

    func clear() {
        expandedGroups.removeAll(keepingCapacity: false)
        checkoutColors.removeAll(keepingCapacity: false)
    }
}
