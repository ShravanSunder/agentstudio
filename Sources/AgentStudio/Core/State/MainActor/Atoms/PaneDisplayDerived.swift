import Foundation

@MainActor
struct PaneDisplayDerived {
    func displayLabel(for paneId: UUID) -> String {
        let workspace = atom(\.workspace)
        let repoCache = atom(\.repoCache)

        guard let pane = workspace.pane(paneId) else {
            return "Unknown"
        }

        if let worktreeId = pane.worktreeId,
            let enrichment = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]
        {
            return enrichment.branch
        }

        return pane.metadata.title
    }
}
