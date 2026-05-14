import Observation

@MainActor
@Observable
final class UIStateAtom {
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false
    private(set) var showMinimizedBars: Bool = true
    private(set) var sidebarCollapsed: Bool = false
    private(set) var sidebarSurface: SidebarSurface = .repos
    /// Runtime-only composition fact published by sidebar surfaces and read by keyboard owner derivation.
    private(set) var sidebarHasFocus: Bool = false

    func setFilterText(_ text: String) {
        filterText = text
    }

    func setFilterVisible(_ isVisible: Bool) {
        isFilterVisible = isVisible
    }

    func setShowMinimizedBars(_ show: Bool) {
        showMinimizedBars = show
    }

    func setSidebarCollapsed(_ isCollapsed: Bool) {
        sidebarCollapsed = isCollapsed
    }

    func setSidebarSurface(_ surface: SidebarSurface) {
        sidebarSurface = surface
    }

    func setSidebarHasFocus(_ hasFocus: Bool) {
        sidebarHasFocus = hasFocus
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        showMinimizedBars: Bool = true,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos
    ) {
        self.filterText = filterText
        self.isFilterVisible = isFilterVisible
        self.showMinimizedBars = showMinimizedBars
        self.sidebarCollapsed = sidebarCollapsed
        self.sidebarSurface = sidebarSurface
        self.sidebarHasFocus = false
    }

    func clear() {
        filterText = ""
        isFilterVisible = false
        showMinimizedBars = true
        sidebarCollapsed = false
        sidebarSurface = .repos
        sidebarHasFocus = false
    }
}
