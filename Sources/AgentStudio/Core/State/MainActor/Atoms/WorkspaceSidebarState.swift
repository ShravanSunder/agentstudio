import Observation

@MainActor
@Observable
final class WorkspaceSidebarMemoryAtom {
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false
    private(set) var sidebarCollapsed: Bool = false
    private(set) var sidebarSurface: SidebarSurface = .repos

    func setFilterText(_ text: String) {
        filterText = text
    }

    func setFilterVisible(_ isVisible: Bool) {
        isFilterVisible = isVisible
    }

    func setSidebarCollapsed(_ isCollapsed: Bool) {
        sidebarCollapsed = isCollapsed
    }

    func setSidebarSurface(_ surface: SidebarSurface) {
        sidebarSurface = surface
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos
    ) {
        self.filterText = filterText
        self.isFilterVisible = isFilterVisible
        self.sidebarCollapsed = sidebarCollapsed
        self.sidebarSurface = sidebarSurface
    }

    func clear() {
        filterText = ""
        isFilterVisible = false
        sidebarCollapsed = false
        sidebarSurface = .repos
    }
}

@MainActor
@Observable
final class SidebarFocusRuntimeAtom {
    /// Runtime-only composition fact published by sidebar surfaces and read by keyboard owner derivation.
    private(set) var sidebarHasFocus: Bool = false

    func setSidebarHasFocus(_ hasFocus: Bool) {
        sidebarHasFocus = hasFocus
    }

    func clear() {
        sidebarHasFocus = false
    }
}

@MainActor
final class WorkspaceSidebarState {
    private let memoryAtom: WorkspaceSidebarMemoryAtom
    private let focusAtom: SidebarFocusRuntimeAtom

    init(
        memoryAtom: WorkspaceSidebarMemoryAtom = .init(),
        focusAtom: SidebarFocusRuntimeAtom = .init()
    ) {
        self.memoryAtom = memoryAtom
        self.focusAtom = focusAtom
    }

    var filterText: String {
        memoryAtom.filterText
    }

    var isFilterVisible: Bool {
        memoryAtom.isFilterVisible
    }

    var sidebarCollapsed: Bool {
        memoryAtom.sidebarCollapsed
    }

    var sidebarSurface: SidebarSurface {
        memoryAtom.sidebarSurface
    }

    var sidebarHasFocus: Bool {
        focusAtom.sidebarHasFocus
    }

    func setFilterText(_ text: String) {
        memoryAtom.setFilterText(text)
    }

    func setFilterVisible(_ isVisible: Bool) {
        memoryAtom.setFilterVisible(isVisible)
    }

    func setSidebarCollapsed(_ isCollapsed: Bool) {
        memoryAtom.setSidebarCollapsed(isCollapsed)
    }

    func setSidebarSurface(_ surface: SidebarSurface) {
        memoryAtom.setSidebarSurface(surface)
    }

    func setSidebarHasFocus(_ hasFocus: Bool) {
        focusAtom.setSidebarHasFocus(hasFocus)
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos
    ) {
        memoryAtom.hydrate(
            filterText: filterText,
            isFilterVisible: isFilterVisible,
            sidebarCollapsed: sidebarCollapsed,
            sidebarSurface: sidebarSurface
        )
        focusAtom.clear()
    }

    func clear() {
        memoryAtom.clear()
        focusAtom.clear()
    }
}
