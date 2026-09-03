import Observation

package enum RepoSidebarGroupingMode: String, CaseIterable, Codable, Hashable, Sendable {
    case repo
    case pane
    case tab
}

@MainActor
@Observable
package final class WorkspaceSidebarMemoryAtom {
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false
    private(set) var sidebarCollapsed: Bool = false
    private(set) var sidebarSurface: SidebarSurface = .repos
    private(set) var repoGroupingMode: RepoSidebarGroupingMode = .repo

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
        _ = surface
        sidebarSurface = .repos
    }

    func setRepoGroupingMode(_ groupingMode: RepoSidebarGroupingMode) {
        repoGroupingMode = groupingMode
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos,
        repoGroupingMode: RepoSidebarGroupingMode = .repo
    ) {
        self.filterText = filterText
        self.isFilterVisible = isFilterVisible
        self.sidebarCollapsed = sidebarCollapsed
        _ = sidebarSurface
        self.sidebarSurface = .repos
        self.repoGroupingMode = repoGroupingMode
    }

    func clear() {
        filterText = ""
        isFilterVisible = false
        sidebarCollapsed = false
        sidebarSurface = .repos
        repoGroupingMode = .repo
    }
}

@MainActor
@Observable
package final class SidebarFocusRuntimeAtom {
    /// Runtime-only composition fact published by sidebar surfaces and read by keyboard owner derivation.
    private(set) var sidebarHasFocus: Bool = false

    package func setSidebarHasFocus(_ hasFocus: Bool) {
        sidebarHasFocus = hasFocus
    }

    func clear() {
        sidebarHasFocus = false
    }
}

@MainActor
package final class WorkspaceSidebarState {
    private let memoryAtom: WorkspaceSidebarMemoryAtom
    private let focusAtom: SidebarFocusRuntimeAtom

    package init(
        memoryAtom: WorkspaceSidebarMemoryAtom = .init(),
        focusAtom: SidebarFocusRuntimeAtom = .init()
    ) {
        self.memoryAtom = memoryAtom
        self.focusAtom = focusAtom
    }

    package var filterText: String {
        memoryAtom.filterText
    }

    package var isFilterVisible: Bool {
        memoryAtom.isFilterVisible
    }

    package var sidebarCollapsed: Bool {
        memoryAtom.sidebarCollapsed
    }

    package var sidebarSurface: SidebarSurface {
        memoryAtom.sidebarSurface
    }

    package var repoGroupingMode: RepoSidebarGroupingMode {
        memoryAtom.repoGroupingMode
    }

    package var sidebarHasFocus: Bool {
        focusAtom.sidebarHasFocus
    }

    package func setFilterText(_ text: String) {
        memoryAtom.setFilterText(text)
    }

    package func setFilterVisible(_ isVisible: Bool) {
        memoryAtom.setFilterVisible(isVisible)
    }

    package func setSidebarCollapsed(_ isCollapsed: Bool) {
        memoryAtom.setSidebarCollapsed(isCollapsed)
    }

    package func setSidebarSurface(_ surface: SidebarSurface) {
        memoryAtom.setSidebarSurface(surface)
    }

    package func setRepoGroupingMode(_ groupingMode: RepoSidebarGroupingMode) {
        memoryAtom.setRepoGroupingMode(groupingMode)
    }

    package func setSidebarHasFocus(_ hasFocus: Bool) {
        focusAtom.setSidebarHasFocus(hasFocus)
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos,
        repoGroupingMode: RepoSidebarGroupingMode = .repo
    ) {
        memoryAtom.hydrate(
            filterText: filterText,
            isFilterVisible: isFilterVisible,
            sidebarCollapsed: sidebarCollapsed,
            sidebarSurface: sidebarSurface,
            repoGroupingMode: repoGroupingMode
        )
        focusAtom.clear()
    }

    func clear() {
        memoryAtom.clear()
        focusAtom.clear()
    }
}
