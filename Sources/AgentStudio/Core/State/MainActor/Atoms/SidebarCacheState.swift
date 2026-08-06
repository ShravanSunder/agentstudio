import Foundation
import Observation

/// Durable sidebar collapsed-group memory. Groups absent from this cache default expanded.
///
/// App-shell composition stays on `WorkspaceSidebarState`; workspace geometry stays on
/// `WorkspaceWindowMemoryAtom`. Do not add focus, selected surface, whole-sidebar collapsed state,
/// or width here.
@MainActor
@Observable
package final class SidebarCollapsedGroupAtom {
    private(set) var collapsedGroups: Set<SidebarGroupKey> = []

    func setGroupExpanded(_ key: SidebarGroupKey, isExpanded: Bool) {
        if isExpanded {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    func setCollapsedGroups(_ groups: Set<SidebarGroupKey>) {
        collapsedGroups = groups
    }

    func hydrate(collapsedGroups: Set<SidebarGroupKey>) {
        self.collapsedGroups = collapsedGroups
    }

    func clear() {
        collapsedGroups.removeAll(keepingCapacity: false)
    }
}

@MainActor
package final class SidebarCacheState {
    private let collapsedGroupAtom: SidebarCollapsedGroupAtom

    // Keep this as a pass-through composition surface. Observation is registered
    // on the child atoms; caching these values here would make SwiftUI and store
    // autosave observers miss direct write-owner mutations.
    init(
        collapsedGroupAtom: SidebarCollapsedGroupAtom = .init()
    ) {
        self.collapsedGroupAtom = collapsedGroupAtom
    }

    package var collapsedGroups: Set<SidebarGroupKey> {
        collapsedGroupAtom.collapsedGroups
    }

    package func setGroupExpanded(_ key: SidebarGroupKey, isExpanded: Bool) {
        collapsedGroupAtom.setGroupExpanded(key, isExpanded: isExpanded)
    }

    func setCollapsedGroups(_ groups: Set<SidebarGroupKey>) {
        collapsedGroupAtom.setCollapsedGroups(groups)
    }

    func hydrate(collapsedGroups: Set<SidebarGroupKey>) {
        collapsedGroupAtom.hydrate(collapsedGroups: collapsedGroups)
    }

    func clear() {
        collapsedGroupAtom.clear()
    }
}
