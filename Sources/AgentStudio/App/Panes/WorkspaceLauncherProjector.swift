import Foundation

enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case choosingFolder
    case scanning(URL)
    case scanEmpty(URL)
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
    let checkoutIconKind: RepoExplorerCheckoutIconKind?
    let iconColorHex: String?
    let repoName: String
    let worktreeDisplayName: String
}

struct WorkspaceEmptyStateModel: Equatable {
    let kind: WorkspaceEmptyStateKind
    let recentCards: [WorkspaceRecentCardModel]

    var scanningFolderPath: URL? {
        if case .scanning(let url) = kind { return url }
        return nil
    }

    var emptyFolderPath: URL? {
        if case .scanEmpty(let url) = kind { return url }
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
        let inboxAtom = atom(\.inboxNotification)
        let welcome = atom(\.welcome)
        let repositoryTopology = atom(\.repositoryTopology)
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )

        if repositoryTopology.repos.isEmpty {
            switch welcome.folderScanState {
            case .idle:
                let kind: WorkspaceEmptyStateKind = welcome.isChoosingFolder ? .choosingFolder : .noFolders
                return WorkspaceEmptyStateModel(kind: kind, recentCards: [])
            case .scanning(let rootPath):
                return WorkspaceEmptyStateModel(kind: .scanning(rootPath), recentCards: [])
            case .empty(let rootPath):
                return WorkspaceEmptyStateModel(kind: .scanEmpty(rootPath), recentCards: [])
            }
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
                    inboxAtom: inboxAtom,
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
        inboxAtom: InboxNotificationAtom,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> [WorkspaceRecentCardModel] {
        recentTargets.compactMap { target in
            projectCard(
                target: target,
                store: store,
                repoCache: repoCache,
                inboxAtom: inboxAtom,
                checkoutColorHexByRepoId: checkoutColorHexByRepoId
            )
        }
    }

    private static func projectCard(
        target: RecentWorkspaceTarget,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        inboxAtom: InboxNotificationAtom,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> WorkspaceRecentCardModel? {
        if let worktreeId = target.worktreeId,
            let worktree = atom(\.repositoryTopology).worktree(worktreeId),
            let repo = atom(\.repositoryTopology).repo(containing: worktreeId)
        {
            return makeWorktreeCard(
                target: target,
                worktree: worktree,
                repo: repo,
                repoCache: repoCache,
                inboxAtom: inboxAtom,
                iconColorHex: checkoutColorHexByRepoId[repo.id]
            )
        }

        if let resolvedContext = atom(\.repositoryTopology).repoAndWorktree(containing: target.path) {
            return makeWorktreeCard(
                target: target,
                worktree: resolvedContext.worktree,
                repo: resolvedContext.repo,
                repoCache: repoCache,
                inboxAtom: inboxAtom,
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
        inboxAtom: InboxNotificationAtom,
        iconColorHex: String?
    ) -> WorkspaceRecentCardModel {
        let worktreeFacts = repoCache.worktreeFacts(for: worktree.id)
        let branchStatus = RepoExplorerView.branchStatus(
            enrichment: worktreeFacts?.enrichment,
            pullRequestCount: worktreeFacts?.pullRequestCount
        )
        let chipModel = WorkspaceStatusChipsModel(
            branchStatus: branchStatus,
            notificationCount: WorkspaceNotificationCountProjection.rollUpAlertCount(
                worktreeId: worktree.id,
                inboxAtom: inboxAtom
            )
        )
        let branchName = atom(\.paneDisplay).resolvedBranchName(
            worktree: worktree,
            enrichment: worktreeFacts?.enrichment
        )

        let worktreeDisplayName: String = {
            if worktree.isMainWorktree { return "main" }
            let prefix = "\(repo.name)."
            if worktree.name.hasPrefix(prefix) {
                return String(worktree.name.dropFirst(prefix.count))
            }
            return worktree.name
        }()

        return WorkspaceRecentCardModel(
            id: target.id,
            target: target,
            title: target.displayTitle,
            detail: branchName,
            icon: worktree.isMainWorktree ? .mainWorktree : .gitWorktree,
            statusChips: chipModel,
            checkoutIconKind: worktree.isMainWorktree ? .mainCheckout : .gitWorktree,
            iconColorHex: iconColorHex ?? fallbackCheckoutColorHex(for: repo),
            repoName: repo.name,
            worktreeDisplayName: worktreeDisplayName
        )
    }

    private static func projectCheckoutColorHexByRepoId(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> [UUID: String] {
        let repoEnrichmentByRepoId = repoCache.repoEnrichmentSnapshot()
        let sidebarRepos = RepoExplorerView.resolvedRepos(
            atom(\.repositoryTopology).repos.map(RepoPresentationItem.init(repo:)),
            enrichmentByRepoId: repoEnrichmentByRepoId
        )
        let metadataByRepoId = RepoPresentationColoring.buildRepoMetadata(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId
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
