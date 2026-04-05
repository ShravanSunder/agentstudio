import Foundation

@MainActor
struct PaneManagementContext: Equatable {
    let title: String
    let detailLine: String
    let statusChips: WorkspaceStatusChipsModel?
    let targetPath: URL?
    let showsIdentityBlock: Bool

    static func project(
        paneId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> Self {
        let parts = PaneDisplayProjector.displayParts(for: paneId, store: store, repoCache: repoCache)
        let pane = store.pane(paneId)
        let resolvedTargetPath = pane?.metadata.cwd ?? pane?.worktreeId.flatMap { store.worktree($0)?.path }
        let title = parts.worktreeFolderName ?? parts.cwdFolderName ?? parts.repoName ?? parts.primaryLabel
        let detailLine = parts.branchName ?? resolvedTargetPath?.path ?? "No filesystem target"
        let hasWorkspaceAssociation =
            pane?.repoId != nil
            || pane?.worktreeId != nil
            || parts.repoName != nil
            || parts.worktreeFolderName != nil
        let showsIdentityBlock: Bool = {
            switch pane?.metadata.contentType {
            case .browser:
                return hasWorkspaceAssociation
            case .none:
                return false
            default:
                return true
            }
        }()

        let statusChips: WorkspaceStatusChipsModel?
        if let worktreeId = pane?.worktreeId {
            let branchStatus = RepoSidebarContentView.branchStatus(
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktreeId],
                pullRequestCount: repoCache.pullRequestCountByWorktreeId[worktreeId]
            )
            statusChips = WorkspaceStatusChipsModel(
                branchStatus: branchStatus,
                notificationCount: repoCache.notificationCountByWorktreeId[worktreeId, default: 0]
            )
        } else if let resolvedWorktreeId = store.repoAndWorktree(containing: pane?.metadata.cwd)?.worktree.id {
            let branchStatus = RepoSidebarContentView.branchStatus(
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[resolvedWorktreeId],
                pullRequestCount: repoCache.pullRequestCountByWorktreeId[resolvedWorktreeId]
            )
            statusChips = WorkspaceStatusChipsModel(
                branchStatus: branchStatus,
                notificationCount: repoCache.notificationCountByWorktreeId[resolvedWorktreeId, default: 0]
            )
        } else {
            statusChips = nil
        }

        return Self(
            title: title,
            detailLine: detailLine,
            statusChips: statusChips,
            targetPath: resolvedTargetPath,
            showsIdentityBlock: showsIdentityBlock
        )
    }
}
