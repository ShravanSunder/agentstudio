import Foundation

struct RepoExplorerSidebarContent {
    let resolvedGroups: [RepoPresentationGroup]
    let loadingRepos: [RepoPresentationItem]
    let showsNoResults: Bool
}

enum RepoExplorerSidebarProjection {
    case ready(RepoExplorerSidebarContent)
    case degraded(RepoExplorerTopologyFault)

    var resolvedGroups: [RepoPresentationGroup] {
        switch self {
        case .ready(let content): content.resolvedGroups
        case .degraded: []
        }
    }

    var loadingRepos: [RepoPresentationItem] {
        switch self {
        case .ready(let content): content.loadingRepos
        case .degraded: []
        }
    }

    var showsNoResults: Bool {
        switch self {
        case .ready(let content): content.showsNoResults
        case .degraded: false
        }
    }
}

enum RepoExplorerProjection {
    static func project(_ snapshot: RepoExplorerSnapshot) -> RepoExplorerSidebarProjection {
        var topologyFaultDetector = RepoExplorerTopologyFaultDetector()
        var resolvedRepos: [RepoPresentationItem] = []
        var loadingRepos: [RepoPresentationItem] = []
        for repo in snapshot.repos {
            topologyFaultDetector.observe(repo)
            switch snapshot.repoEnrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                resolvedRepos.append(repo)
            case .awaitingOrigin, .none:
                loadingRepos.append(repo)
            }
        }
        if let topologyFault = topologyFaultDetector.fault {
            return .degraded(topologyFault)
        }

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

        return .ready(
            RepoExplorerSidebarContent(
                resolvedGroups: resolvedGroups,
                loadingRepos: filteredLoadingRepos,
                showsNoResults: !snapshot.query.isEmpty && resolvedGroups.isEmpty && filteredLoadingRepos.isEmpty
            )
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
