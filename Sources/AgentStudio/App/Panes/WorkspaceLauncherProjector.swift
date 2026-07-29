import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioRepoExplorer
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
    let target: ApplicationRecentEntity
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

    var recentEntities: [ApplicationRecentEntity] {
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
        inboxAtom: InboxNotificationAtom
    ) -> WorkspaceEmptyStateModel {
        let repoCache = atom(\.repoCache)
        let welcome = atom(\.welcome)
        let repositoryTopology = store.repositoryTopologyAtom
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
            let applicationRecency = atom(\.applicationEntityRecency)
            let checkoutColorHexByRepoId = projectCheckoutColorHexByRepoId(
                store: store,
                repoCache: repoCache
            )
            let visibleCards = Array(
                projectRecentCards(
                    recentEntities: applicationRecency.recentEntities,
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
        recentEntities: [ApplicationEntityRecency],
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        inboxAtom: InboxNotificationAtom,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> [WorkspaceRecentCardModel] {
        recentEntities.compactMap { recency in
            projectCard(
                target: recency.entity,
                store: store,
                repoCache: repoCache,
                inboxAtom: inboxAtom,
                checkoutColorHexByRepoId: checkoutColorHexByRepoId
            )
        }
    }

    private static func projectCard(
        target: ApplicationRecentEntity,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        inboxAtom: InboxNotificationAtom,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> WorkspaceRecentCardModel? {
        switch target {
        case .repository(let repositoryStableKey):
            guard
                let repo = store.repositoryTopologyAtom.repo(stableKey: repositoryStableKey),
                !store.repositoryTopologyAtom.isRepoUnavailable(repo.id),
                let worktree = canonicalDefaultWorktree(in: repo)
            else {
                return nil
            }
            return makeWorktreeCard(
                target: target,
                worktree: worktree,
                repo: repo,
                repoCache: repoCache,
                inboxAtom: inboxAtom,
                iconColorHex: checkoutColorHexByRepoId[repo.id]
            )
        case .worktree(let worktreeStableKey):
            guard
                let worktree = store.repositoryTopologyAtom.worktree(stableKey: worktreeStableKey),
                let repo = store.repositoryTopologyAtom.repo(containing: worktree.id),
                !store.repositoryTopologyAtom.isRepoUnavailable(repo.id)
            else {
                return nil
            }
            return makeWorktreeCard(
                target: target,
                worktree: worktree,
                repo: repo,
                repoCache: repoCache,
                inboxAtom: inboxAtom,
                iconColorHex: checkoutColorHexByRepoId[repo.id]
            )
        }
    }

    private static func makeWorktreeCard(
        target: ApplicationRecentEntity,
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
            id: "recent:\(target.storageKind):\(target.storageKey)",
            target: target,
            title: cardTitle(target: target, repo: repo, worktree: worktree),
            detail: branchName,
            icon: worktree.isMainWorktree ? .mainWorktree : .gitWorktree,
            statusChips: chipModel,
            checkoutIconKind: worktree.isMainWorktree ? .mainCheckout : .gitWorktree,
            iconColorHex: iconColorHex ?? fallbackCheckoutColorHex(for: repo),
            repoName: repo.name,
            worktreeDisplayName: worktreeDisplayName
        )
    }

    static func resolveActivationWorktree(
        target: ApplicationRecentEntity,
        repositoryTopology: RepositoryTopologyAtom
    ) -> Worktree? {
        repositoryTopology.activationWorktree(for: target)
    }

    static func pruneStaleTarget(
        _ target: ApplicationRecentEntity,
        applicationRecency: ApplicationEntityRecencyAtom
    ) {
        applicationRecency.remove(target)
    }

    private static func canonicalDefaultWorktree(in repo: Repo) -> Worktree? {
        repo.worktrees.first(where: \.isMainWorktree) ?? repo.worktrees.first
    }

    private static func cardTitle(
        target: ApplicationRecentEntity,
        repo: Repo,
        worktree: Worktree
    ) -> String {
        switch target {
        case .repository:
            repo.name
        case .worktree:
            worktree.name
        }
    }

    private static func projectCheckoutColorHexByRepoId(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> [UUID: String] {
        let repoEnrichmentByRepoId = repoCache.repoEnrichmentSnapshot()
        let sidebarRepos = RepoExplorerView.resolvedRepos(
            store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:)),
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
