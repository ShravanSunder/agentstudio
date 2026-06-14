import Foundation

struct RepoExplorerSnapshot {
    let repos: [RepoPresentationItem]
    let repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    let query: String
}
