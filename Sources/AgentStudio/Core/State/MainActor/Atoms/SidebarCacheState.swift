import Foundation
import Observation

/// Durable sidebar expanded-group memory that can safely default without changing workspace meaning.
///
/// App-shell composition stays on `WorkspaceSidebarState`; workspace geometry stays on
/// `WorkspaceWindowMemoryAtom`. Do not add focus, selected surface, collapsed state,
/// or width here.
@MainActor
@Observable
final class SidebarExpandedGroupAtom {
    private(set) var expandedGroups: Set<SidebarGroupKey> = []

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

    func hydrate(expandedGroups: Set<SidebarGroupKey>) {
        self.expandedGroups = expandedGroups
    }

    func clear() {
        expandedGroups.removeAll(keepingCapacity: false)
    }
}

/// User-selected checkout color memory kept separate from expanded group state.
@MainActor
@Observable
final class SidebarCheckoutColorAtom {
    private(set) var checkoutColors: [SidebarCheckoutColorKey: String] = [:]

    func setCheckoutColor(_ colorHex: String?, for key: SidebarCheckoutColorKey) {
        if let colorHex {
            checkoutColors[key] = colorHex
        } else {
            checkoutColors.removeValue(forKey: key)
        }
    }

    func hydrate(checkoutColors: [SidebarCheckoutColorKey: String]) {
        self.checkoutColors = checkoutColors
    }

    func clear() {
        checkoutColors.removeAll(keepingCapacity: false)
    }
}

@MainActor
final class SidebarCacheState {
    private let expandedGroupAtom: SidebarExpandedGroupAtom
    private let checkoutColorAtom: SidebarCheckoutColorAtom

    // Keep this as a pass-through composition surface. Observation is registered
    // on the child atoms; caching these values here would make SwiftUI and store
    // autosave observers miss direct write-owner mutations.
    init(
        expandedGroupAtom: SidebarExpandedGroupAtom = .init(),
        checkoutColorAtom: SidebarCheckoutColorAtom = .init()
    ) {
        self.expandedGroupAtom = expandedGroupAtom
        self.checkoutColorAtom = checkoutColorAtom
    }

    var expandedGroups: Set<SidebarGroupKey> {
        expandedGroupAtom.expandedGroups
    }

    var checkoutColors: [SidebarCheckoutColorKey: String] {
        checkoutColorAtom.checkoutColors
    }

    func setGroupExpanded(_ key: SidebarGroupKey, isExpanded: Bool) {
        expandedGroupAtom.setGroupExpanded(key, isExpanded: isExpanded)
    }

    func setExpandedGroups(_ groups: Set<SidebarGroupKey>) {
        expandedGroupAtom.setExpandedGroups(groups)
    }

    func setCheckoutColor(_ colorHex: String?, for key: SidebarCheckoutColorKey) {
        checkoutColorAtom.setCheckoutColor(colorHex, for: key)
    }

    func hydrate(
        expandedGroups: Set<SidebarGroupKey>,
        checkoutColors: [SidebarCheckoutColorKey: String]
    ) {
        expandedGroupAtom.hydrate(expandedGroups: expandedGroups)
        checkoutColorAtom.hydrate(checkoutColors: checkoutColors)
    }

    func clear() {
        expandedGroupAtom.clear()
        checkoutColorAtom.clear()
    }
}
