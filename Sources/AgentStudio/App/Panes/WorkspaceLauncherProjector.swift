import Foundation

enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case scanning(URL)
    case launcher
}

enum WorkspaceHomeCardIcon: Equatable {
    case mainWorktree
    case gitWorktree
    case cwdOnly
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
    static func project(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> WorkspaceEmptyStateModel {
        // Scanning takes priority when no repos exist yet
        if let scanningPath = store.scanningPath, store.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .scanning(scanningPath), recentCards: [])
        }

        if store.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .noFolders, recentCards: [])
        }

        if store.tabs.isEmpty {
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
        repoCache: WorkspaceRepoCache,
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
        repoCache: WorkspaceRepoCache,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> WorkspaceRecentCardModel? {
        if let worktreeId = target.worktreeId,
            let worktree = store.worktree(worktreeId),
            let repo = store.repo(containing: worktreeId)
        {
            return makeWorktreeCard(
                target: target,
                worktree: worktree,
                repo: repo,
                repoCache: repoCache,
                iconColorHex: checkoutColorHexByRepoId[repo.id]
            )
        }

        if let resolvedContext = store.repoAndWorktree(containing: target.path) {
            return makeWorktreeCard(
                target: target,
                worktree: resolvedContext.worktree,
                repo: resolvedContext.repo,
                repoCache: repoCache,
                iconColorHex: checkoutColorHexByRepoId[resolvedContext.repo.id]
            )
        }

        return WorkspaceRecentCardModel(
            id: target.id,
            target: target,
            title: target.displayTitle,
            detail: target.subtitle,
            icon: .cwdOnly,
            statusChips: nil,
            checkoutIconKind: nil,
            iconColorHex: nil
        )
    }

    private static func makeWorktreeCard(
        target: RecentWorkspaceTarget,
        worktree: Worktree,
        repo: Repo,
        repoCache: WorkspaceRepoCache,
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
        let branchName = PaneDisplayProjector.resolvedBranchName(
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
        repoCache: WorkspaceRepoCache
    ) -> [UUID: String] {
        let sidebarRepos = RepoSidebarContentView.resolvedRepos(
            store.repos.map(SidebarRepo.init(repo:)),
            enrichmentByRepoId: repoCache.repoEnrichmentByRepoId
        )
        let metadataByRepoId = RepoSidebarContentView.buildRepoMetadata(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId
        )
        let groups = SidebarRepoGrouping.buildGroups(
            repos: sidebarRepos,
            metadataByRepoId: metadataByRepoId
        )

        var checkoutColorHexByRepoId: [UUID: String] = [:]
        for group in groups {
            for repo in group.repos {
                checkoutColorHexByRepoId[repo.id] = RepoSidebarContentView.checkoutColorHex(
                    for: repo,
                    in: group
                )
            }
        }
        return checkoutColorHexByRepoId
    }

    private static func fallbackCheckoutColorHex(for repo: Repo) -> String {
        RepoSidebarContentView.checkoutColorHex(
            for: SidebarRepo(repo: repo),
            in: SidebarRepoGroup(
                id: "path:\(repo.repoPath.standardizedFileURL.path)",
                repoTitle: repo.name,
                organizationName: nil,
                repos: [SidebarRepo(repo: repo)]
            )
        )
    }
}
