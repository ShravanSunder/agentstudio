import Observation

package enum RepoSidebarGroupingMode: String, CaseIterable, Codable, Hashable, Sendable {
    case repo
    case tab
    case activity
}

package enum SidebarSubgroupMode: String, CaseIterable, Codable, Hashable, Sendable {
    case ungrouped = "none"
    case activity
}

package enum SidebarSortField: String, CaseIterable, Codable, Hashable, Sendable {
    case name
    case activity
}

package enum SidebarSortDirection: String, CaseIterable, Codable, Hashable, Sendable {
    case ascending
    case descending

    package static let `default`: Self = .ascending

    package var toggled: Self {
        switch self {
        case .ascending: .descending
        case .descending: .ascending
        }
    }
}

@MainActor
@Observable
package final class WorkspaceSidebarMemoryAtom {
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false
    private(set) var sidebarCollapsed: Bool = false
    private(set) var sidebarSurface: SidebarSurface = .repos
    private(set) var repoGroupingMode: RepoSidebarGroupingMode = .repo
    private(set) var paneGroupingMode: RepoSidebarGroupingMode = .repo
    private(set) var repoSubgroupMode: SidebarSubgroupMode = .ungrouped
    private(set) var paneSubgroupMode: SidebarSubgroupMode = .activity
    private(set) var showsPinnedRepos: Bool = true
    private(set) var showsPinnedPanes: Bool = true

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
        sidebarSurface = surface == .inbox ? .repos : surface
    }

    func setRepoGroupingMode(_ groupingMode: RepoSidebarGroupingMode) {
        repoGroupingMode = groupingMode
    }

    func setPaneGroupingMode(_ groupingMode: RepoSidebarGroupingMode) {
        paneGroupingMode = groupingMode
    }

    func setRepoSubgroupMode(_ subgroupMode: SidebarSubgroupMode) {
        repoSubgroupMode = subgroupMode
    }

    func setPaneSubgroupMode(_ subgroupMode: SidebarSubgroupMode) {
        paneSubgroupMode = subgroupMode
    }

    func setShowsPinnedRepos(_ showsPinned: Bool) {
        showsPinnedRepos = showsPinned
    }

    func setShowsPinnedPanes(_ showsPinned: Bool) {
        showsPinnedPanes = showsPinned
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos,
        repoGroupingMode: RepoSidebarGroupingMode = .repo,
        paneGroupingMode: RepoSidebarGroupingMode = .repo,
        repoSubgroupMode: SidebarSubgroupMode = .ungrouped,
        paneSubgroupMode: SidebarSubgroupMode = .activity,
        showsPinnedRepos: Bool = true,
        showsPinnedPanes: Bool = true
    ) {
        self.filterText = filterText
        self.isFilterVisible = isFilterVisible
        self.sidebarCollapsed = sidebarCollapsed
        self.sidebarSurface = sidebarSurface == .inbox ? .repos : sidebarSurface
        self.repoGroupingMode = repoGroupingMode
        self.paneGroupingMode = paneGroupingMode
        self.repoSubgroupMode = repoSubgroupMode
        self.paneSubgroupMode = paneSubgroupMode
        self.showsPinnedRepos = showsPinnedRepos
        self.showsPinnedPanes = showsPinnedPanes
    }

    func clear() {
        filterText = ""
        isFilterVisible = false
        sidebarCollapsed = false
        sidebarSurface = .repos
        repoGroupingMode = .repo
        paneGroupingMode = .repo
        repoSubgroupMode = .ungrouped
        paneSubgroupMode = .activity
        showsPinnedRepos = true
        showsPinnedPanes = true
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

    package var paneGroupingMode: RepoSidebarGroupingMode { memoryAtom.paneGroupingMode }
    package var repoSubgroupMode: SidebarSubgroupMode { memoryAtom.repoSubgroupMode }
    package var paneSubgroupMode: SidebarSubgroupMode { memoryAtom.paneSubgroupMode }
    package var showsPinnedRepos: Bool { memoryAtom.showsPinnedRepos }
    package var showsPinnedPanes: Bool { memoryAtom.showsPinnedPanes }

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

    package func setPaneGroupingMode(_ groupingMode: RepoSidebarGroupingMode) {
        memoryAtom.setPaneGroupingMode(groupingMode)
    }

    package func setRepoSubgroupMode(_ subgroupMode: SidebarSubgroupMode) {
        memoryAtom.setRepoSubgroupMode(subgroupMode)
    }

    package func setPaneSubgroupMode(_ subgroupMode: SidebarSubgroupMode) {
        memoryAtom.setPaneSubgroupMode(subgroupMode)
    }

    package func setShowsPinnedRepos(_ showsPinned: Bool) {
        memoryAtom.setShowsPinnedRepos(showsPinned)
    }

    package func setShowsPinnedPanes(_ showsPinned: Bool) {
        memoryAtom.setShowsPinnedPanes(showsPinned)
    }

    package func setSidebarHasFocus(_ hasFocus: Bool) {
        focusAtom.setSidebarHasFocus(hasFocus)
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos,
        repoGroupingMode: RepoSidebarGroupingMode = .repo,
        paneGroupingMode: RepoSidebarGroupingMode = .repo,
        repoSubgroupMode: SidebarSubgroupMode = .ungrouped,
        paneSubgroupMode: SidebarSubgroupMode = .activity,
        showsPinnedRepos: Bool = true,
        showsPinnedPanes: Bool = true
    ) {
        memoryAtom.hydrate(
            filterText: filterText,
            isFilterVisible: isFilterVisible,
            sidebarCollapsed: sidebarCollapsed,
            sidebarSurface: sidebarSurface,
            repoGroupingMode: repoGroupingMode,
            paneGroupingMode: paneGroupingMode,
            repoSubgroupMode: repoSubgroupMode,
            paneSubgroupMode: paneSubgroupMode,
            showsPinnedRepos: showsPinnedRepos,
            showsPinnedPanes: showsPinnedPanes
        )
        focusAtom.clear()
    }

    func clear() {
        memoryAtom.clear()
        focusAtom.clear()
    }
}
