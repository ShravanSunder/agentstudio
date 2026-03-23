import Foundation

struct PaneDisplayParts: Equatable {
    let primaryLabel: String
    let repoName: String?
    let branchName: String?
    let worktreeFolderName: String?
    let cwdFolderName: String?
}

@MainActor
enum PaneDisplayProjector {
    static func displayParts(
        for paneId: UUID,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> PaneDisplayParts {
        guard let pane = store.pane(paneId) else {
            return PaneDisplayParts(
                primaryLabel: "Terminal",
                repoName: nil,
                branchName: nil,
                worktreeFolderName: nil,
                cwdFolderName: nil
            )
        }

        return displayParts(for: pane, store: store, repoCache: repoCache)
    }

    static func displayParts(
        for pane: Pane,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> PaneDisplayParts {
        let rawTitle = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLabel = rawTitle.isEmpty ? "Terminal" : rawTitle
        let cwdFolderName: String? = {
            guard let cwdFolder = pane.metadata.cwd?.lastPathComponent else { return nil }
            return cwdFolder.isEmpty ? nil : cwdFolder
        }()

        if let worktreeId = pane.worktreeId,
            let repoId = pane.repoId,
            let repo = store.repo(repoId),
            let worktree = store.worktree(worktreeId)
        {
            let repoName = pane.metadata.repoName ?? repo.name
            let branchName = resolvedBranchName(
                worktree: worktree,
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
            )
            let worktreeFolderName = worktree.path.lastPathComponent
            return PaneDisplayParts(
                primaryLabel: "\(repoName) | \(branchName) | \(worktreeFolderName)",
                repoName: repoName,
                branchName: branchName,
                worktreeFolderName: worktreeFolderName,
                cwdFolderName: cwdFolderName
            )
        }

        if let cwdFolderName {
            return PaneDisplayParts(
                primaryLabel: cwdFolderName,
                repoName: nil,
                branchName: nil,
                worktreeFolderName: nil,
                cwdFolderName: cwdFolderName
            )
        }

        return PaneDisplayParts(
            primaryLabel: defaultLabel,
            repoName: nil,
            branchName: nil,
            worktreeFolderName: nil,
            cwdFolderName: nil
        )
    }

    static func displayLabel(
        for paneId: UUID,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> String {
        displayParts(for: paneId, store: store, repoCache: repoCache).primaryLabel
    }

    static func tabDisplayLabel(
        for tab: Tab,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> String {
        let paneLabels = tab.paneIds.map { displayLabel(for: $0, store: store, repoCache: repoCache) }
        if paneLabels.count > 1 {
            return paneLabels.joined(separator: " | ")
        }
        return paneLabels.first ?? "Terminal"
    }

    static func paneKeywords(
        for pane: Pane,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> [String] {
        let parts = displayParts(for: pane, store: store, repoCache: repoCache)
        return [parts.primaryLabel, parts.repoName, parts.branchName, parts.worktreeFolderName, parts.cwdFolderName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    static func resolvedBranchName(
        worktree: Worktree,
        enrichment: WorktreeEnrichment?
    ) -> String {
        let cachedBranch = enrichment?.branch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cachedBranch.isEmpty {
            return cachedBranch
        }

        return "detached HEAD"
    }
}
