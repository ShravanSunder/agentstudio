import Foundation
import Observation

/// User-preference UI state for workspace/sidebar presentation.
@Observable
@MainActor
final class WorkspaceUIStore {
    private(set) var expandedGroups: Set<String> = []
    private(set) var checkoutColors: [String: String] = [:]
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false

    func setExpandedGroups(_ groups: Set<String>) {
        expandedGroups = groups
    }

    func setGroupExpanded(_ groupKey: String, isExpanded: Bool) {
        if isExpanded {
            expandedGroups.insert(groupKey)
        } else {
            expandedGroups.remove(groupKey)
        }
    }

    func setCheckoutColor(_ colorHex: String?, for stableKey: String) {
        if let colorHex {
            checkoutColors[stableKey] = colorHex
        } else {
            checkoutColors.removeValue(forKey: stableKey)
        }
    }

    func setFilterText(_ text: String) {
        filterText = text
    }

    func setFilterVisible(_ isVisible: Bool) {
        isFilterVisible = isVisible
    }

    func clear() {
        expandedGroups.removeAll(keepingCapacity: false)
        checkoutColors.removeAll(keepingCapacity: false)
        filterText = ""
        isFilterVisible = false
    }
}
