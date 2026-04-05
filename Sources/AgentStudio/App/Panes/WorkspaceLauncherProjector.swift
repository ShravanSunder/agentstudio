import Foundation

enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
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
}

struct WorkspaceEmptyStateModel: Equatable {
    let kind: WorkspaceEmptyStateKind
    let recentCards: [WorkspaceRecentCardModel]

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
        store: WorkspaceStore
    ) -> WorkspaceEmptyStateModel {
        let repoCache = atom(\.repoCache)
        if store.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .noFolders, recentCards: [])
        }

        if store.tabs.isEmpty {
            let visibleCards = Array(
                projectRecentCards(
                    recentTargets: repoCache.recentTargets,
                    store: store,
                    repoCache: repoCache
                )
                .prefix(6)
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
        repoCache: RepoCacheAtom
    ) -> [WorkspaceRecentCardModel] {
        recentTargets.compactMap { target in
            projectCard(
                target: target,
                store: store,
                repoCache: repoCache
            )
        }
    }

    private static func projectCard(
        target: RecentWorkspaceTarget,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> WorkspaceRecentCardModel? {
        if let worktreeId = target.worktreeId,
            let worktree = store.worktree(worktreeId)
        {
            return makeWorktreeCard(
                target: target,
                worktree: worktree,
                repoCache: repoCache
            )
        }

        if let resolvedContext = store.repoAndWorktree(containing: target.path) {
            return makeWorktreeCard(
                target: target,
                worktree: resolvedContext.worktree,
                repoCache: repoCache
            )
        }

        return WorkspaceRecentCardModel(
            id: target.id,
            target: target,
            title: target.displayTitle,
            detail: target.subtitle,
            icon: .cwdOnly,
            statusChips: nil
        )
    }

    private static func makeWorktreeCard(
        target: RecentWorkspaceTarget,
        worktree: Worktree,
        repoCache: RepoCacheAtom
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
            statusChips: chipModel
        )
    }
}
