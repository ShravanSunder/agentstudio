import Foundation

enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case scanning(URL)
    case launcher
}

enum WorkspaceHomeCardIcon: Equatable {
    case mainWorktree
    case gitWorktree
}

struct WorkspaceRecentCardModel: Equatable, Identifiable {
    let id: String
    let target: RecentWorkspaceTarget
    let title: String
    let detail: String
    let icon: WorkspaceHomeCardIcon
    let statusChips: WorkspaceStatusChipsModel?
    let checkoutIconKind: SidebarCheckoutIconKind?
    let iconColorHex: String?
}

struct WorkspaceEmptyStateModel: Equatable {
    let kind: WorkspaceEmptyStateKind
    let recentCards: [WorkspaceRecentCardModel]

    var scanningFolderPath: URL? {
        if case .scanning(let url) = kind { return url }
        return nil
    }

    var recentTargets: [RecentWorkspaceTarget] {
        recentCards.map(\.target)
    }

    var showsOpenAll: Bool {
        recentCards.count > 1
    }
}

@MainActor
enum WorkspaceLauncherProjector {
    static func project(store: WorkspaceStore) -> WorkspaceEmptyStateModel {
        let repoCache = atom(\.repoCache)
        let repositoryTopology = store.repositoryTopologyAtom
        let workspaceTab = WorkspaceTabDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )

        if let scanningPath = store.scanningPath, repositoryTopology.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .scanning(scanningPath), recentCards: [])
        }

        if repositoryTopology.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .noFolders, recentCards: [])
        }

        if workspaceTab.tabs.isEmpty {
            let checkoutColorHexByRepoId = projectCheckoutColorHexByRepoId(
                store: store,
                repoCache: repoCache
            )
            let visibleCards = Array(
                projectRecentCards(
                    recentTargets: repoCache.recentTargets,
                    store: store,
                    repoCache: repoCache,
                    checkoutColorHexByRepoId: checkoutColorHexByRepoId
                )
                .prefix(15)
            )

            return WorkspaceEmptyStateModel(
                kind: .launcher,
                recentCards: visibleCards
            )
        }

        return WorkspaceEmptyStateModel(kind: .launcher, recentCards: [])
    }

    private static func projectRecentCards(
        recentTargets: [RecentWorkspaceTarget],
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> [WorkspaceRecentCardModel] {
        recentTargets.compactMap { target in
            projectCard(
                target: target,
                store: store,
                repoCache: repoCache,
                checkoutColorHexByRepoId: checkoutColorHexByRepoId
            )
        }
    }

    private static func projectCard(
        target: RecentWorkspaceTarget,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> WorkspaceRecentCardModel? {
        if let worktreeId = target.worktreeId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
            let repo = store.repositoryTopologyAtom.repo(containing: worktreeId)
        {
            return makeWorktreeCard(
                target: target,
                worktree: worktree,
                repo: repo,
                repoCache: repoCache,
                iconColorHex: checkoutColorHexByRepoId[repo.id]
            )
        }

        if let resolvedContext = store.repositoryTopologyAtom.repoAndWorktree(containing: target.path) {
            return makeWorktreeCard(
                target: target,
                worktree: resolvedContext.worktree,
                repo: resolvedContext.repo,
                repoCache: repoCache,
                iconColorHex: checkoutColorHexByRepoId[resolvedContext.repo.id]
            )
        }

        return nil
    }

    private static func makeWorktreeCard(
        target: RecentWorkspaceTarget,
        worktree: Worktree,
        repo: Repo,
        repoCache: RepoCacheAtom,
        iconColorHex: String?
    ) -> WorkspaceRecentCardModel {
        let branchStatus = RepoSidebarContentView.branchStatus(
            enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id],
            pullRequestCount: repoCache.pullRequestCountByWorktreeId[worktree.id]
        )
        let chipModel = WorkspaceStatusChipsModel(
            branchStatus: branchStatus,
            notificationCount: repoCache.notificationCountByWorktreeId[worktree.id, default: 0]
        )
        let branchName = atom(\.paneDisplay).resolvedBranchName(
            worktree: worktree,
            enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
        )

        return WorkspaceRecentCardModel(
            id: target.id,
            target: target,
            title: target.displayTitle,
            detail: branchName,
            icon: worktree.isMainWorktree ? .mainWorktree : .gitWorktree,
            statusChips: chipModel,
            checkoutIconKind: worktree.isMainWorktree ? .mainCheckout : .gitWorktree,
            iconColorHex: iconColorHex ?? fallbackCheckoutColorHex(for: repo)
        )
    }

    private static func projectCheckoutColorHexByRepoId(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> [UUID: String] {
        let sidebarRepos = RepoSidebarContentView.resolvedRepos(
            store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:)),
            enrichmentByRepoId: repoCache.repoEnrichmentByRepoId
        )
        let metadataByRepoId = RepoPresentationColoring.buildRepoMetadata(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId
        )
        let groups = RepoPresentationGrouping.buildGroups(
            repos: sidebarRepos,
            metadataByRepoId: metadataByRepoId
        )

        var checkoutColorHexByRepoId: [UUID: String] = [:]
        for group in groups {
            for repo in group.repos {
                checkoutColorHexByRepoId[repo.id] = RepoPresentationColoring.checkoutColorHex(
                    for: repo,
                    in: group
                )
            }
        }
        return checkoutColorHexByRepoId
    }

    private static func fallbackCheckoutColorHex(for repo: Repo) -> String {
        RepoPresentationColoring.checkoutColorHex(
            for: RepoPresentationItem(repo: repo),
            in: RepoPresentationGroup(
                id: "path:\(repo.repoPath.standardizedFileURL.path)",
                repoTitle: repo.name,
                organizationName: nil,
                repos: [RepoPresentationItem(repo: repo)]
            )
        )
    }
}
