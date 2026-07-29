import Observation

@MainActor
@Observable
package final class RepoExplorerSidebarPrefsAtom {
    package private(set) var groupingMode: RepoExplorerGroupingMode = .repo
    package private(set) var sortOrder: RepoExplorerSortOrder = .default
    package private(set) var repoVisibilityMode: RepoExplorerVisibilityMode = .all

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

    package func setRepoVisibilityMode(_ mode: RepoExplorerVisibilityMode) {
        repoVisibilityMode = mode
    }

    package func hydrate(
        groupingMode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder,
        repoVisibilityMode: RepoExplorerVisibilityMode
    ) {
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
        self.repoVisibilityMode = repoVisibilityMode
    }

    package func reset() {
        groupingMode = .repo
        sortOrder = .default
        repoVisibilityMode = .all
    }
}
