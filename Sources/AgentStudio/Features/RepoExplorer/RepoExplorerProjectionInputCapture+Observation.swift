import AgentStudioCore
import Foundation

enum RepoExplorerObservationToken: Hashable, Sendable {
    case demand
    case presentation
    case membership
    case repository(UUID)
    case worktree(UUID)
    case paneStructure(UUID)
    case pane(UUID)
    case tabStructure(UUID)
    case tab(UUID)
    case attention
    case activityHydration
    case repositoryActivity(UUID)
}

enum RepoExplorerInputInvalidation: Equatable, Sendable {
    case structural
    case presentation
    case repository(UUID)
    case worktree(UUID)
    case pane(UUID)
    case tab(UUID)
    case attention
    case activityHydration
    case repositoryActivity(UUID)
}

struct RepoExplorerScopedCapture: Sendable {
    let request: RepoExplorerProjectionRequest
    let changes: Set<RepoExplorerScopedProjectionChange>
    let requiresFullProjection: Bool
}

extension RepoExplorerProjectionInputCapture {
    func observe(_ token: RepoExplorerObservationToken, request: RepoExplorerProjectionRequest?) {
        switch token {
        case .demand:
            _ = sidebarState.sidebarSurface
        case .presentation:
            _ = preferences.groupingMode
            if request?.snapshot.groupingMode != .tab {
                _ = preferences.sortOrder
            }
            _ = sidebarCache.collapsedGroups
        case .membership:
            _ = store.repositoryTopologyAtom.repositoryIdsInOrder
            _ = store.paneAtom.graphAtom.paneIDs
            _ = store.tabShellAtom.orderedTabIds
        case .repository(let repositoryID):
            _ = store.repositoryTopologyAtom.repo(repositoryID)
            _ = repoCache.repoEnrichment(for: repositoryID)
            _ = repoCache.isPullRequestLoading(forRepository: repositoryID)
            _ = repoCache.isPullRequestDataUnavailable(forRepository: repositoryID)
            _ = repoCache.repositoryFactUpdateProgress(for: repositoryID)
        case .worktree(let worktreeID):
            _ = store.repositoryTopologyAtom.worktree(worktreeID)
            let enrichment = repoCache.worktreeEnrichment(for: worktreeID)
            if let enrichment,
                let branchKey = RepoBranchKey(repoId: enrichment.repoId, branch: enrichment.branch)
            {
                _ = repoCache.pullRequestFacts(for: branchKey)
            }
        case .paneStructure(let paneID):
            _ = store.paneAtom.graphAtom.paneStructuralFacts(paneID)
        case .pane(let paneID):
            _ = store.paneAtom.pane(paneID)
            _ = latestPaneMessageSnapshot(paneID)
            _ = bridgeAttendanceSnapshot(paneID)
            _ = coreAtoms.workspaceEntityRecency.recency(for: .pane(paneID: paneID))
        case .tabStructure(let tabID):
            _ = store.tabArrangementAtom.arrangementState(tabID)
        case .tab(let tabID):
            guard let tab = store.tabLayoutAtom.tab(tabID) else { return }
            _ = coreAtoms.tabDisplay.displayTitle(
                for: tab,
                workspacePane: store.paneAtom,
                workspaceRepositoryTopology: store.repositoryTopologyAtom,
                repoCache: repoCache
            )
        case .attention:
            _ = KeyboardRoutingContext.current(
                windowLifecycle: coreAtoms.windowLifecycle,
                managementLayer: coreAtoms.managementLayer,
                uiState: sidebarState,
                commandBarSurface: coreAtoms.commandBarSurface,
                transientKeyboardSurface: coreAtoms.transientKeyboardSurface
            )
            _ = coreAtoms.attendedPane.attendedPaneId
        case .activityHydration:
            _ = coreAtoms.repositoryLocalActivity.hydrationDisposition
        case .repositoryActivity(let repositoryID):
            guard
                let repositoryStableKey = request?.snapshot.repos.first(where: {
                    $0.id == repositoryID
                })?.stableKey
            else { return }
            _ = coreAtoms.repositoryLocalActivity.activity(for: repositoryStableKey)
        }
    }

    func observationTokens(for request: RepoExplorerProjectionRequest) -> Set<RepoExplorerObservationToken> {
        let structuralPaneIDs = demandedPaneIDs(in: request.snapshot)
        let structuralTabIDs = demandedTabIDs(in: request.snapshot)
        var tokens: Set<RepoExplorerObservationToken> = [
            .demand, .presentation, .membership, .activityHydration,
        ]
        tokens.formUnion(request.snapshot.repos.map { .repository($0.id) })
        tokens.formUnion(request.snapshot.repos.map { .repositoryActivity($0.id) })
        tokens.formUnion(request.snapshot.repos.flatMap(\.worktrees).map { .worktree($0.id) })
        tokens.formUnion(structuralPaneIDs.map(RepoExplorerObservationToken.paneStructure))
        tokens.formUnion(structuralTabIDs.map(RepoExplorerObservationToken.tabStructure))
        if request.snapshot.groupingMode != .repo {
            tokens.formUnion(structuralPaneIDs.map(RepoExplorerObservationToken.pane))
            tokens.insert(.attention)
        }
        if request.snapshot.groupingMode == .tab {
            tokens.formUnion(structuralTabIDs.map(RepoExplorerObservationToken.tab))
        }
        return tokens
    }

    func invalidation(for token: RepoExplorerObservationToken) -> RepoExplorerInputInvalidation {
        switch token {
        case .demand, .membership, .paneStructure, .tabStructure:
            .structural
        case .presentation:
            .presentation
        case .repository(let repositoryID):
            .repository(repositoryID)
        case .worktree(let worktreeID):
            .worktree(worktreeID)
        case .pane(let paneID):
            .pane(paneID)
        case .tab(let tabID):
            .tab(tabID)
        case .attention:
            .attention
        case .activityHydration:
            .activityHydration
        case .repositoryActivity(let repositoryID):
            .repositoryActivity(repositoryID)
        }
    }
}
