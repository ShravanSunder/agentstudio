import AgentStudioCore
import Observation

@MainActor
@Observable
package final class RepoExplorerSidebarPrefsAtom {
    private let sidebarState: WorkspaceSidebarState
    package private(set) var sortOrder: RepoExplorerSortOrder = .default

    package var groupingMode: RepoExplorerGroupingMode {
        sidebarState.repoGroupingMode
    }

    package init(sidebarState: WorkspaceSidebarState = .init()) {
        self.sidebarState = sidebarState
    }

    package func setGroupingMode(_ groupingMode: RepoExplorerGroupingMode) {
        sidebarState.setRepoGroupingMode(groupingMode)
    }

    package func toggleSortOrder() {
        sortOrder = sortOrder.toggled
    }

    package func setSortOrder(_ sortOrder: RepoExplorerSortOrder) {
        self.sortOrder = sortOrder
    }

    package func hydrate(
        sortOrder: RepoExplorerSortOrder
    ) {
        self.sortOrder = sortOrder
    }

    package func reset() {
        sortOrder = .default
    }
}
