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

    var icon: CommandIcon {
        switch self {
        case .repo:
            return .system(.folder)
        case .pane:
            return .system(.rectangleSplit2x1)
        case .tab:
            return .system(.rectangleStack)
        }
    }
}

enum RepoExplorerSortOrder: String, CaseIterable, Codable, Hashable, Sendable {
    case ascending
    case descending

    static let `default`: Self = .ascending

    var toggled: Self {
        switch self {
        case .ascending:
            return .descending
        case .descending:
            return .ascending
        }
    }

    var title: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }
}

enum RepoExplorerVisibilityMode: String, CaseIterable, Codable, Hashable, Sendable {
    case all
    case favoritesOnly
}

struct RepoExplorerSnapshot: Equatable, Sendable {
    let repos: [RepoPresentationItem]
    let repoEnrichmentSnapshotByRepoId: [UUID: RepoEnrichment]
    let groupingMode: RepoExplorerGroupingMode
    let sortOrder: RepoExplorerSortOrder
    let visibilityMode: RepoExplorerVisibilityMode
    let query: String
    let paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]]

    init(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode = .repo,
        sortOrder: RepoExplorerSortOrder = .default,
        visibilityMode: RepoExplorerVisibilityMode = .all,
        query: String,
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:]
    ) {
        self.repos = repos
        self.repoEnrichmentSnapshotByRepoId = repoEnrichmentByRepoId
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
        self.visibilityMode = visibilityMode
        self.query = query
        self.paneLocationsByWorktreeId = paneLocationsByWorktreeId
    }
}
