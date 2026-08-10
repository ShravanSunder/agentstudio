import Foundation

@MainActor
package struct TabDisplayDerived {
    package func displayTitle(
        for tab: Tab,
        workspacePane: WorkspacePaneAtom,
        workspaceRepositoryTopology: RepositoryTopologyAtom,
        repoCache: RepoCacheAtom
    ) -> String {
        Self.displayTitle(for: tab) { paneId in
            workspacePane.pane(paneId).map {
                title(
                    for: $0,
                    workspaceRepositoryTopology: workspaceRepositoryTopology,
                    repoCache: repoCache
                )
            }
        }
    }

    package func title(
        for pane: Pane,
        workspaceRepositoryTopology: RepositoryTopologyAtom,
        repoCache: RepoCacheAtom
    ) -> String {
        let worktree = pane.worktreeId.flatMap(workspaceRepositoryTopology.worktree(_:))
        return Self.title(
            for: pane,
            worktree: worktree,
            enrichment: worktree.flatMap { repoCache.worktreeEnrichment(for: $0.id) }
        )
    }

    nonisolated package static func displayTitle(
        for tab: Tab,
        cancellationCheck: () throws(CancellationError) -> Void = {},
        titleForPane: (UUID) -> String?
    ) throws(CancellationError) -> String {
        let normalizedName = Tab.normalizedName(tab.name)
        if !normalizedName.isEmpty, normalizedName != "Tab" {
            return normalizedName
        }

        var paneTitles: [String] = []
        paneTitles.reserveCapacity(tab.activePaneIds.count)
        for paneId in tab.activePaneIds {
            try cancellationCheck()
            if let title = titleForPane(paneId) {
                paneTitles.append(title)
            }
        }
        if paneTitles.count > 1 {
            return paneTitles.joined(separator: " | ")
        }
        return paneTitles.first ?? "Terminal"
    }

    nonisolated package static func displayTitle(
        for tab: Tab,
        titleForPane: (UUID) -> String?
    ) -> String {
        // The non-throwing reader supplies no cancellation source.
        try! displayTitle(for: tab, cancellationCheck: {}, titleForPane: titleForPane)
    }

    nonisolated package static func title(
        for pane: Pane,
        worktree: Worktree?,
        enrichment: WorktreeEnrichment?
    ) -> String {
        if let worktree {
            let branchName = PaneDisplayDerived.resolvedBranchName(
                worktree: worktree,
                enrichment: enrichment
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
