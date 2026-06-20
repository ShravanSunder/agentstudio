import Observation

@MainActor
@Observable
final class RepoExplorerSidebarPrefsAtom {
    private(set) var groupingMode: RepoExplorerGroupingMode = .repo

    func setGroupingMode(_ groupingMode: RepoExplorerGroupingMode) {
        self.groupingMode = groupingMode
    }

    func hydrate(groupingMode: RepoExplorerGroupingMode) {
        self.groupingMode = groupingMode
    }

    func reset() {
        groupingMode = .repo
    }
}
