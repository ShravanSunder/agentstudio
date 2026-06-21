import Observation

@MainActor
@Observable
final class RepoExplorerSidebarPrefsAtom {
    private(set) var groupingMode: RepoExplorerGroupingMode = .repo
    private(set) var sortOrder: RepoExplorerSortOrder = .default

    func setGroupingMode(_ groupingMode: RepoExplorerGroupingMode) {
        self.groupingMode = groupingMode
    }

    func toggleSortOrder() {
        sortOrder = sortOrder.toggled
    }

    func setSortOrder(_ sortOrder: RepoExplorerSortOrder) {
        self.sortOrder = sortOrder
    }

    func hydrate(groupingMode: RepoExplorerGroupingMode, sortOrder: RepoExplorerSortOrder) {
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
    }

    func reset() {
        groupingMode = .repo
        sortOrder = .default
    }
}
