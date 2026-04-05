import Foundation

struct PaneDisplayParts: Equatable {
    let primaryLabel: String
    let repoName: String?
    let branchName: String?
    let worktreeFolderName: String?
    let cwdFolderName: String?
}

@MainActor
struct PaneDisplayDerived {
    func displayParts(for paneId: UUID) -> PaneDisplayParts {
        let workspacePane = atom(\.workspacePane)
        guard let pane = workspacePane.pane(paneId) else {
            return PaneDisplayParts(
                primaryLabel: "Terminal",
                repoName: nil,
                branchName: nil,
                worktreeFolderName: nil,
                cwdFolderName: nil
            )
        }

        return displayParts(for: pane)
    }

    func displayParts(for pane: Pane) -> PaneDisplayParts {
        let workspaceRepositoryTopology = atom(\.workspaceRepositoryTopology)
        let repoCache = atom(\.repoCache)

        let rawTitle = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLabel = rawTitle.isEmpty ? "Terminal" : rawTitle
        let cwdFolderName: String? = {
            guard let cwdFolder = pane.metadata.cwd?.lastPathComponent else { return nil }
            return cwdFolder.isEmpty ? nil : cwdFolder
        }()

        if let worktreeId = pane.worktreeId,
            let repoId = pane.repoId,
            let repo = workspaceRepositoryTopology.repo(repoId),
            let worktree = workspaceRepositoryTopology.worktree(worktreeId)
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

    func displayLabel(for paneId: UUID) -> String {
        displayParts(for: paneId).primaryLabel
    }

    func tabDisplayLabel(for tab: Tab) -> String {
        let paneLabels = tab.paneIds.map { displayLabel(for: $0) }
        if paneLabels.count > 1 {
            return paneLabels.joined(separator: " | ")
        }
        return paneLabels.first ?? "Terminal"
    }

    func paneKeywords(for pane: Pane) -> [String] {
        let parts = displayParts(for: pane)
        return [parts.primaryLabel, parts.repoName, parts.branchName, parts.worktreeFolderName, parts.cwdFolderName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    func resolvedBranchName(
        worktree _: Worktree,
        enrichment: WorktreeEnrichment?
    ) -> String {
        let cachedBranch = enrichment?.branch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cachedBranch.isEmpty {
            return cachedBranch
        }

        return "detached HEAD"
    }
}
