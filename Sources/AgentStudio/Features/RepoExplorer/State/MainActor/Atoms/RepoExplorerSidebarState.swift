import Observation

@MainActor
@Observable
package final class RepoExplorerSidebarPrefsAtom {
    package private(set) var groupingMode: RepoExplorerGroupingMode = .repo
    package private(set) var sortOrder: RepoExplorerSortOrder = .default

    package init() {}

    package func setGroupingMode(_ groupingMode: RepoExplorerGroupingMode) {
        self.groupingMode = groupingMode
    }

    package func toggleSortOrder() {
        sortOrder = sortOrder.toggled
    }

    package func setSortOrder(_ sortOrder: RepoExplorerSortOrder) {
        self.sortOrder = sortOrder
    }

    package func hydrate(
        groupingMode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder
    ) {
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
    }

    package func reset() {
        groupingMode = .repo
        sortOrder = .default
    }
}
