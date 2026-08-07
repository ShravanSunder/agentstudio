import Foundation
import os.log

private let arrangementDerivedLogger = Logger(subsystem: "com.agentstudio", category: "ArrangementDerived")

@MainActor
package struct ArrangementDerived {
    nonisolated package static func nextCustomArrangementName(existing: [PaneArrangement]) -> String {
        let existingNames = Set(existing.map(\.name))
        var index = 1
        while existingNames.contains("Layout \(index)") {
            index += 1
        }
        return "Layout \(index)"
    }

    package func paneVisibilityItems(for tabId: UUID) -> [PaneVisibilityInfo] {
        let workspaceTab = atom(\.workspaceTab)
        let workspacePane = atom(\.workspacePane)
        let paneDisplay = atom(\.paneDisplay)
        guard let tab = workspaceTab.tab(tabId) else {
            arrangementDerivedLogger.warning("paneVisibilityItems: tab \(tabId) not found")
            return []
        }

        return tab.activePaneIds.map { paneId in
            Self.paneVisibilityInfo(
                paneId: paneId,
                title: paneDisplay.displayLabel(for: paneId),
                isMinimized: tab.activeMinimizedPaneIds.contains(paneId),
                paneContent: workspacePane.pane(paneId)?.content
            )
        }
    }

    package func arrangementItems(for tabId: UUID) -> [ArrangementInfo] {
        let workspaceTab = atom(\.workspaceTab)
        guard let tab = workspaceTab.tab(tabId) else {
            arrangementDerivedLogger.warning("arrangementItems: tab \(tabId) not found")
            return []
        }

        return tab.arrangements.map { arrangement in
            Self.arrangementInfo(
                for: arrangement,
                activeArrangementId: tab.activeArrangementId
            )
        }
    }

    package func zoomMode(for tabId: UUID) -> ArrangementPanelZoomMode? {
        guard
            let presentation = atom(\.workspacePanePresentation)
                .zoomPresentation(forTab: tabId)
        else {
            return nil
        }

        return Self.zoomMode(
            presentation: presentation,
            sourceIdentity: zoomSourceIdentity(for: presentation.sourcePaneId)
        )
    }

    func nextCustomArrangementName(for tabId: UUID) -> String? {
        let workspaceTab = atom(\.workspaceTab)
        guard let tab = workspaceTab.tab(tabId) else {
            arrangementDerivedLogger.warning("nextCustomArrangementName: tab \(tabId) not found")
            return nil
        }
        return Self.nextCustomArrangementName(existing: tab.arrangements)
    }

    nonisolated package static func paneVisibilityInfo(
        paneId: UUID,
        title: String,
        isMinimized: Bool,
        paneContent: PaneContent?
    ) -> PaneVisibilityInfo {
        PaneVisibilityInfo(
            id: paneId,
            title: title,
            isMinimized: isMinimized,
            supportsZoom: paneContent.map(ZoomCommandCapabilityPolicy.isPaneContentEligible(_:)) ?? false
        )
    }

    nonisolated package static func arrangementInfo(
        for arrangement: PaneArrangement,
        activeArrangementId: UUID
    ) -> ArrangementInfo {
        ArrangementInfo(
            id: arrangement.id,
            name: arrangement.name,
            role: arrangement.isDefault ? .defaultArrangement : .userLayout,
            isActive: arrangement.id == activeArrangementId
        )
    }

    nonisolated package static func zoomMode(
        presentation: ZoomPresentation,
        sourceIdentity: ArrangementPanelZoomSourceIdentity?
    ) -> ArrangementPanelZoomMode {
        ArrangementPanelZoomMode(
            label: "Cancel Zoom",
            sourcePaneId: presentation.sourcePaneId,
            sourceIdentity: sourceIdentity
        )
    }

    nonisolated package static func activeArrangementBadgeNumber(for tab: Tab) -> Int? {
        let customArrangements = tab.arrangements.filter { !$0.isDefault }
        guard let index = customArrangements.firstIndex(where: { $0.id == tab.activeArrangementId }) else {
            return nil
        }
        return index + 1
    }

    nonisolated package static func activeArrangementDisplayName(
        for arrangement: PaneArrangement
    ) -> String {
        arrangement.isDefault ? "Default" : arrangement.name
    }

    nonisolated package static func zoomSourceIdentity(
        for sourcePane: Pane,
        workspaceContext: PaneDisplayWorkspaceContext?
    ) -> ArrangementPanelZoomSourceIdentity {
        let sourceLabels: [String]
        if let workspaceContext {
            sourceLabels = [
                workspaceContext.repoName,
                workspaceContext.branchName,
                workspaceContext.worktreeName,
            ]
            .compactMap { $0 }
        } else {
            sourceLabels = [
                sourcePane.metadata.facets.repoName,
                sourcePane.metadata.facets.worktreeName,
            ]
            .compactMap { label in
                let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        let sourceTitle =
            sourceLabels.isEmpty
            ? PaneDisplayDerived.displayParts(for: sourcePane, workspaceContext: workspaceContext).primaryLabel
            : sourceLabels.joined(separator: " | ")
        let targetPath = sourcePane.metadata.cwd

        return ArrangementPanelZoomSourceIdentity(
            title: sourceTitle,
            detail: targetPath?.standardizedFileURL.path,
            fullPath: targetPath?.standardizedFileURL.path
        )
    }

    nonisolated package static func zoomSourceWorkspaceContext(
        resolvedContext: (repo: Repo, worktree: Worktree)?,
        worktreeEnrichment: WorktreeEnrichment?
    ) -> PaneDisplayWorkspaceContext? {
        guard let resolvedContext else { return nil }
        return PaneDisplayWorkspaceContext(
            repoName: resolvedContext.repo.name,
            worktreeName: resolvedContext.worktree.path.lastPathComponent,
            worktreeIconName: resolvedContext.worktree.isMainWorktree
                ? "octicon-star-fill" : "octicon-git-worktree",
            branchName: PaneDisplayDerived.resolvedBranchName(
                worktree: resolvedContext.worktree,
                enrichment: worktreeEnrichment
            )
        )
    }

    private func zoomSourceIdentity(
        for sourcePaneId: UUID
    ) -> ArrangementPanelZoomSourceIdentity? {
        let workspacePane = atom(\.workspacePane)
        let repositoryTopology = atom(\.workspaceRepositoryTopology)
        let repoCache = atom(\.repoCache)
        guard let sourcePane = workspacePane.pane(sourcePaneId) else {
            return nil
        }
        let resolvedContext =
            sourcePane.worktreeId.flatMap { worktreeId in
                sourcePane.repoId.flatMap { repoId in
                    repositoryTopology.repo(repoId).flatMap { repo in
                        repositoryTopology.worktree(worktreeId).map { (repo, $0) }
                    }
                }
            }
            ?? repositoryTopology.repoAndWorktree(containing: sourcePane.metadata.cwd)
        let workspaceContext = Self.zoomSourceWorkspaceContext(
            resolvedContext: resolvedContext,
            worktreeEnrichment: resolvedContext.flatMap {
                repoCache.worktreeEnrichment(for: $0.worktree.id)
            }
        )
        return Self.zoomSourceIdentity(
            for: sourcePane,
            workspaceContext: workspaceContext
        )
    }
}
