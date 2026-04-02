import Foundation

@MainActor
struct PaneManagementContext: Equatable {
    let title: String
    let subtitle: String
    let targetPath: URL?

    static func project(
        paneId: UUID,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> Self {
        let parts = PaneDisplayProjector.displayParts(for: paneId, store: store, repoCache: repoCache)
        let pane = store.pane(paneId)
        let resolvedTargetPath = pane?.metadata.cwd ?? pane?.worktreeId.flatMap { store.worktree($0)?.path }

        let subtitleParts = [
            parts.repoName,
            parts.branchName,
            parts.worktreeFolderName ?? parts.cwdFolderName,
        ]
        let subtitle =
            subtitleParts
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        return Self(
            title: parts.primaryLabel,
            subtitle: subtitle.isEmpty ? (resolvedTargetPath?.path ?? "No filesystem target") : subtitle,
            targetPath: resolvedTargetPath
        )
    }
}
