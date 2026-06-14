import Foundation

struct RepoExplorerSidebarProjection {
    let resolvedGroups: [RepoPresentationGroup]
    let loadingRepos: [RepoPresentationItem]
    let showsNoResults: Bool
}

enum RepoExplorerProjection {
    static func project(_ snapshot: RepoExplorerSnapshot) -> RepoExplorerSidebarProjection {
        let resolvedRepos = resolvedRepos(snapshot.repos, enrichmentByRepoId: snapshot.repoEnrichmentByRepoId)
        let loadingRepos = loadingRepos(snapshot.repos, enrichmentByRepoId: snapshot.repoEnrichmentByRepoId)
        let filteredResolvedRepos = RepoExplorerFilter.filter(repos: resolvedRepos, query: snapshot.query)
        let filteredLoadingRepos = filterLoadingRepos(loadingRepos, query: snapshot.query)
        let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
            repos: filteredResolvedRepos,
            repoEnrichmentByRepoId: snapshot.repoEnrichmentByRepoId
        )
        let resolvedGroups = RepoPresentationGrouping.buildGroups(
            repos: filteredResolvedRepos,
            metadataByRepoId: repoMetadataById
        )

        return RepoExplorerSidebarProjection(
            resolvedGroups: resolvedGroups,
            loadingRepos: filteredLoadingRepos,
            showsNoResults: !snapshot.query.isEmpty && resolvedGroups.isEmpty && filteredLoadingRepos.isEmpty
        )
    }

    static func resolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return true
            case .awaitingOrigin, .none:
                return false
            }
        }
    }

    static func loadingRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return false
            case .awaitingOrigin, .none:
                return true
            }
        }
    }

    private static func filterLoadingRepos(
        _ repos: [RepoPresentationItem],
        query: String
    ) -> [RepoPresentationItem] {
        let filteredRepos: [RepoPresentationItem]
        if query.isEmpty {
            filteredRepos = repos
        } else {
            filteredRepos = repos.filter { repo in
                repo.name.localizedCaseInsensitiveContains(query)
            }
        }

        return filteredRepos.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
