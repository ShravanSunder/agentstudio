import Foundation
import Observation

@MainActor
@Observable
final class UIStateAtom {
    private(set) var expandedGroups: Set<String> = []
    private(set) var checkoutColors: [String: String] = [:]
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false
    private(set) var showMinimizedBars: Bool = true

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

    func setShowMinimizedBars(_ show: Bool) {
        showMinimizedBars = show
    }

    func hydrate(
        expandedGroups: Set<String>,
        checkoutColors: [String: String],
        filterText: String,
        isFilterVisible: Bool,
        showMinimizedBars: Bool = true
    ) {
        self.expandedGroups = expandedGroups
        self.checkoutColors = checkoutColors
        self.filterText = filterText
        self.isFilterVisible = isFilterVisible
        self.showMinimizedBars = showMinimizedBars
    }

    func clear() {
        expandedGroups.removeAll(keepingCapacity: false)
        checkoutColors.removeAll(keepingCapacity: false)
        filterText = ""
        isFilterVisible = false
        showMinimizedBars = true
    }
}
