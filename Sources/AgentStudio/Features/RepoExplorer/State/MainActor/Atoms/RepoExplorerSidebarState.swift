import Observation

@MainActor
@Observable
final class RepoExplorerSidebarPrefsAtom {
    private(set) var groupingMode: RepoExplorerGroupingMode = .repo
    private(set) var sortOrder: RepoExplorerSortOrder = .default
    private(set) var repoVisibilityMode: RepoExplorerVisibilityMode = .all

    func setGroupingMode(_ groupingMode: RepoExplorerGroupingMode) {
        self.groupingMode = groupingMode
    }

    func toggleSortOrder() {
        sortOrder = sortOrder.toggled
    }

    func setSortOrder(_ sortOrder: RepoExplorerSortOrder) {
        self.sortOrder = sortOrder
    }

    func setRepoVisibilityMode(_ mode: RepoExplorerVisibilityMode) {
        repoVisibilityMode = mode
    }

    func hydrate(
        groupingMode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder,
        repoVisibilityMode: RepoExplorerVisibilityMode
    ) {
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
        self.repoVisibilityMode = repoVisibilityMode
    }

    func reset() {
        groupingMode = .repo
        sortOrder = .default
        repoVisibilityMode = .all
    }
}
