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

@MainActor
final class SidebarCacheState {
    private let expandedGroupAtom: SidebarExpandedGroupAtom

    // Keep this as a pass-through composition surface. Observation is registered
    // on the child atoms; caching these values here would make SwiftUI and store
    // autosave observers miss direct write-owner mutations.
    init(
        expandedGroupAtom: SidebarExpandedGroupAtom = .init()
    ) {
        self.expandedGroupAtom = expandedGroupAtom
    }

    var expandedGroups: Set<SidebarGroupKey> {
        expandedGroupAtom.expandedGroups
    }

    func setGroupExpanded(_ key: SidebarGroupKey, isExpanded: Bool) {
        expandedGroupAtom.setGroupExpanded(key, isExpanded: isExpanded)
    }

    func setExpandedGroups(_ groups: Set<SidebarGroupKey>) {
        expandedGroupAtom.setExpandedGroups(groups)
    }

    func hydrate(expandedGroups: Set<SidebarGroupKey>) {
        expandedGroupAtom.hydrate(expandedGroups: expandedGroups)
    }

    func clear() {
        expandedGroupAtom.clear()
    }
}
