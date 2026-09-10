import AgentStudioCore
import Observation

@MainActor
@Observable
package final class RepoExplorerSidebarPrefsAtom {
    private let sidebarState: WorkspaceSidebarState
    package private(set) var repoSortField: SidebarSortField = .name
    package private(set) var paneSortField: SidebarSortField = .name
    package private(set) var repoSortDirection: SidebarSortDirection = .default
    package private(set) var paneSortDirection: SidebarSortDirection = .default

    package var groupingMode: RepoExplorerGroupingMode {
        groupingMode(for: sidebarState.sidebarSurface)
    }

    package var sidebarSurface: SidebarSurface {
        sidebarState.sidebarSurface
    }

    package var subgroupMode: SidebarSubgroupMode {
        subgroupMode(for: sidebarState.sidebarSurface)
    }

    package var sortField: SidebarSortField {
        sortField(for: sidebarState.sidebarSurface)
    }

    package var sortDirection: SidebarSortDirection {
        sortDirection(for: sidebarState.sidebarSurface)
    }

    package var showsPinned: Bool {
        showsPinned(for: sidebarState.sidebarSurface)
    }

    package init(sidebarState: WorkspaceSidebarState = .init()) {
        self.sidebarState = sidebarState
    }

    package func groupingMode(for surface: SidebarSurface) -> RepoExplorerGroupingMode {
        switch surface {
        case .panes:
            sidebarState.paneGroupingMode
        case .repos, .inbox:
            switch sidebarState.repoGroupingMode {
            case .repo, .activity:
                sidebarState.repoGroupingMode
            case .tab:
                .repo
            }
        }
    }

    package func subgroupMode(for surface: SidebarSurface) -> SidebarSubgroupMode {
        switch surface {
        case .panes:
            groupingMode(for: surface) == .activity ? .ungrouped : sidebarState.paneSubgroupMode
        case .repos, .inbox:
            .ungrouped
        }
    }

    package func sortField(for surface: SidebarSurface) -> SidebarSortField {
        switch surface {
        case .panes:
            paneSortField
        case .repos, .inbox:
            repoSortField
        }
    }

    package func sortDirection(for surface: SidebarSurface) -> SidebarSortDirection {
        switch surface {
        case .panes:
            paneSortDirection
        case .repos, .inbox:
            repoSortDirection
        }
    }

    package func showsPinned(for surface: SidebarSurface) -> Bool {
        switch surface {
        case .panes:
            sidebarState.showsPinnedPanes
        case .repos, .inbox:
            sidebarState.showsPinnedRepos
        }
    }

    package func setGroupingMode(_ groupingMode: RepoExplorerGroupingMode, for surface: SidebarSurface) {
        switch surface {
        case .panes:
            sidebarState.setPaneGroupingMode(groupingMode)
        case .repos, .inbox:
            sidebarState.setRepoGroupingMode(groupingMode == .tab ? .repo : groupingMode)
        }
    }

    package func setSubgroupMode(_ subgroupMode: SidebarSubgroupMode, for surface: SidebarSurface) {
        switch surface {
        case .panes:
            sidebarState.setPaneSubgroupMode(subgroupMode)
        case .repos, .inbox:
            break
        }
    }

    package func setSortField(_ sortField: SidebarSortField, for surface: SidebarSurface) {
        switch surface {
        case .panes:
            paneSortField = sortField
        case .repos, .inbox:
            repoSortField = sortField
        }
    }

    package func setSortDirection(_ sortDirection: SidebarSortDirection, for surface: SidebarSurface) {
        switch surface {
        case .panes:
            paneSortDirection = sortDirection
        case .repos, .inbox:
            repoSortDirection = sortDirection
        }
    }

    package func setShowsPinned(_ showsPinned: Bool, for surface: SidebarSurface) {
        switch surface {
        case .panes:
            sidebarState.setShowsPinnedPanes(showsPinned)
        case .repos, .inbox:
            sidebarState.setShowsPinnedRepos(showsPinned)
        }
    }

    package func hydrate(
        repoSortField: SidebarSortField,
        paneSortField: SidebarSortField,
        repoSortDirection: SidebarSortDirection,
        paneSortDirection: SidebarSortDirection
    ) {
        self.repoSortField = repoSortField
        self.paneSortField = paneSortField
        self.repoSortDirection = repoSortDirection
        self.paneSortDirection = paneSortDirection
    }

    package func reset() {
        repoSortField = .name
        paneSortField = .name
        repoSortDirection = .default
        paneSortDirection = .default
    }
}
