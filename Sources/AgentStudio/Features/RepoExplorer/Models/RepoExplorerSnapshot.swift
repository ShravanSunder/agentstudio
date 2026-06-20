import Foundation

enum RepoExplorerGroupingMode: String, CaseIterable, Codable, Hashable, Sendable {
    case repo
    case pane
    case tab

    var title: String {
        switch self {
        case .repo:
            return "Repo"
        case .pane:
            return "Pane"
        case .tab:
            return "Tab"
        }
    }
}

struct RepoExplorerSnapshot {
    let repos: [RepoPresentationItem]
    let repoEnrichmentSnapshotByRepoId: [UUID: RepoEnrichment]
    let groupingMode: RepoExplorerGroupingMode
    let query: String
    let paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]]

    init(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode = .repo,
        query: String,
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:]
    ) {
        self.repos = repos
        self.repoEnrichmentSnapshotByRepoId = repoEnrichmentByRepoId
        self.groupingMode = groupingMode
        self.query = query
        self.paneLocationsByWorktreeId = paneLocationsByWorktreeId
    }
}
