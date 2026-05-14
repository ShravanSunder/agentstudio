import Foundation

@MainActor
struct TabDisplayDerived {
    func displayTitle(
        for tab: Tab,
        workspacePane: WorkspacePaneAtom,
        workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom,
        repoCache: RepoCacheAtom
    ) -> String {
        let normalizedName = Tab.normalizedName(tab.name)
        if !normalizedName.isEmpty, normalizedName != "Tab" {
            return normalizedName
        }

        let paneTitles = tab.activePaneIds.compactMap { paneId in
            workspacePane.pane(paneId).map {
                title(
                    for: $0,
                    workspaceRepositoryTopology: workspaceRepositoryTopology,
                    repoCache: repoCache
                )
            }
        }
        if paneTitles.count > 1 {
            return paneTitles.joined(separator: " | ")
        }
        return paneTitles.first ?? "Terminal"
    }

    func title(
        for pane: Pane,
        workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom,
        repoCache: RepoCacheAtom
    ) -> String {
        if let worktreeId = pane.worktreeId,
            let worktree = workspaceRepositoryTopology.worktree(worktreeId)
        {
            let branchName = atom(\.paneDisplay).resolvedBranchName(
                worktree: worktree,
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
            )
            let folderName = worktree.path.lastPathComponent

            if branchName == "detached HEAD" || branchName.isEmpty {
                return folderName
            }
            if branchName == folderName {
                return branchName
            }
            return "\(folderName) · \(branchName)"
        }

        let title = pane.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Terminal" : title
    }

}
