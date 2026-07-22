import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func repairRestoredBridgePanesAfterInitialTopologyReplay() {
        guard let activeTab = store.tabLayoutAtom.activeTab,
            let fallbackPaneId = activeTab.activePaneId ?? activeTab.activePaneIds.first
        else { return }

        let renderedPaneIds = PaneObservationResolver.currentRenderedPaneIds(
            activeTab: activeTab,
            fallbackPaneId: fallbackPaneId
        )
        for paneId in renderedPaneIds {
            guard let pane = store.paneAtom.pane(paneId),
                case .bridgePanel(let state) = pane.content,
                let controller = viewRegistry.view(for: paneId)?
                    .mountedContent(as: BridgePaneMountView.self)?.controller,
                controller.runtime.metadata.repoId == nil
                    || controller.runtime.metadata.worktreeId == nil
            else { continue }

            let repairedMetadata = bridgePaneControllerMetadata(for: pane, state: state)
            guard repairedMetadata.repoId != nil,
                repairedMetadata.worktreeId != nil
            else { continue }

            execute(.repair(.recreateSurface(paneId: paneId)))
        }
    }

    func bridgePaneControllerMetadata(for pane: Pane, state: BridgePaneState) -> PaneMetadata {
        var metadata = pane.metadata
        guard metadata.repoId == nil || metadata.worktreeId == nil else {
            return metadata
        }
        guard let rootURL = bridgeMetadataRepairRootURL(metadata: metadata, state: state) else {
            return metadata
        }
        guard let context = bridgeWorkspaceContext(forRootPath: rootURL.path) else {
            return metadata
        }
        metadata.updateFacets(
            metadata.facets.fillingNilFields(
                from: PaneContextFacets(
                    repoId: context.repo.id,
                    repoName: context.repo.name,
                    worktreeId: context.worktree.id,
                    worktreeName: context.worktree.name,
                    cwd: context.worktree.path
                )
            )
        )
        return metadata
    }

    private func bridgeMetadataRepairRootURL(
        metadata: PaneMetadata,
        state: BridgePaneState
    ) -> URL? {
        if case .workspace(let rootPath, _)? = state.source {
            return URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        }
        guard state.panelKind == .fileViewer else {
            return nil
        }
        return (metadata.cwd ?? metadata.launchDirectory)?.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func bridgeWorkspaceContext(forRootPath rootPath: String) -> (repo: Repo, worktree: Worktree)? {
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        var bestMatch: (repo: Repo, worktree: Worktree, pathLength: Int)?
        for repo in store.repositoryTopologyAtom.repos {
            for worktree in repo.worktrees {
                let worktreeURL = worktree.path.standardizedFileURL.resolvingSymlinksInPath()
                let worktreePath = worktreeURL.path
                let rootPath = rootURL.path
                guard rootPath == worktreePath || rootPath.hasPrefix(worktreePath + "/") else {
                    continue
                }
                if bestMatch == nil || worktreePath.count > bestMatch!.pathLength {
                    bestMatch = (repo: repo, worktree: worktree, pathLength: worktreePath.count)
                }
            }
        }
        guard let bestMatch else { return nil }
        return (repo: bestMatch.repo, worktree: bestMatch.worktree)
    }
}
