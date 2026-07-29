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
            PaneVisibilityInfo(
                id: paneId,
                title: paneDisplay.displayLabel(for: paneId),
                isMinimized: tab.activeMinimizedPaneIds.contains(paneId),
                supportsZoom: workspacePane.pane(paneId).map {
                    ZoomCommandCapabilityPolicy.isPaneContentEligible($0.content)
                } ?? false
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
            ArrangementInfo(
                id: arrangement.id,
                name: arrangement.name,
                role: arrangement.isDefault ? .defaultArrangement : .userLayout,
                isActive: arrangement.id == tab.activeArrangementId
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

        return ArrangementPanelZoomMode(
            label: "Cancel Zoom",
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

    private func zoomSourceIdentity(
        for sourcePaneId: UUID
    ) -> ArrangementPanelZoomSourceIdentity? {
        let workspacePane = atom(\.workspacePane)
        let repositoryTopology = atom(\.workspaceRepositoryTopology)
        let repoCache = atom(\.repoCache)
        let paneDisplay = atom(\.paneDisplay)
        guard let sourcePane = workspacePane.pane(sourcePaneId) else {
            return nil
        }

        let resolvedContext =
            sourcePane.worktreeId.flatMap { worktreeId in
                sourcePane.repoId.flatMap { repoId in
                    repositoryTopology.repo(repoId).flatMap { repo in
                        repositoryTopology.worktree(worktreeId).map { (repo: repo, worktree: $0) }
                    }
                }
            }
            ?? repositoryTopology.repoAndWorktree(containing: sourcePane.metadata.cwd)

        let sourceLabels: [String]
        if let resolvedContext {
            sourceLabels = [
                resolvedContext.repo.name,
                paneDisplay.resolvedBranchName(
                    worktree: resolvedContext.worktree,
                    enrichment: repoCache.worktreeEnrichment(for: resolvedContext.worktree.id)
                ),
                resolvedContext.worktree.path.lastPathComponent,
            ]
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
            ? paneDisplay.displayLabel(for: sourcePaneId)
            : sourceLabels.joined(separator: " | ")
        let targetPath = sourcePane.metadata.cwd

        return ArrangementPanelZoomSourceIdentity(
            title: sourceTitle,
            detail: targetPath?.standardizedFileURL.path,
            fullPath: targetPath?.standardizedFileURL.path
        )
    }
}
