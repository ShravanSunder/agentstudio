import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func retireZoomCompanion(forSourcePane sourcePaneId: UUID) {
        let companion = store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePaneId
        )
        store.panePresentationAtom.removeZoomSourcePane(sourcePaneId)
        guard let companion else { return }
        retireZoomCompanionResources(companion)
        refreshBridgePaneActivities()
    }

    private func retireLostZoomCompanion(
        forSourcePane sourcePaneId: UUID,
        viewerWorktreeStillResolves: Bool
    ) {
        let companion = store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePaneId
        )
        store.panePresentationAtom.markZoomCompanionLost(
            forSourcePane: sourcePaneId,
            viewerWorktreeStillResolves: viewerWorktreeStillResolves
        )
        if let companion {
            retireZoomCompanionResources(companion)
        }
        refreshBridgePaneActivities()
    }

    private func retireZoomCompanionResources(
        _ companion: ZoomCompanionMetadata
    ) {
        teardownView(for: companion.companionPaneId)
        retireBridgePaneActivityAuthority(for: companion.companionPaneId)
        viewRegistry.retireSlot(for: companion.companionPaneId)
    }

    func recoverZoomCompanionAfterResourceLoss(for companionPaneId: UUID) {
        guard
            let retainedCompanion = store.panePresentationAtom.zoomCompanionsBySourcePaneId
                .first(where: { $0.value.companionPaneId == companionPaneId }),
            viewRegistry.allBridgeViews[companionPaneId] == nil
                || runtimeForPane(PaneId(existingUUID: companionPaneId)) == nil
        else {
            return
        }

        let sourcePaneId = retainedCompanion.key
        let companion = retainedCompanion.value
        let resolvedContext = zoomCompanionContext(
            sourcePaneId: sourcePaneId,
            owningTabId: companion.owningTabId
        )
        retireLostZoomCompanion(
            forSourcePane: sourcePaneId,
            viewerWorktreeStillResolves: resolvedContext?.worktree.id
                == companion.resolvedWorktreeId
        )
    }

    func retireZoomCompanions(forSourcePanes sourcePaneIds: some Sequence<UUID>) {
        for sourcePaneId in sourcePaneIds {
            retireZoomCompanion(forSourcePane: sourcePaneId)
        }
    }

    func retireAllZoomCompanions() {
        retireZoomCompanions(
            forSourcePanes: Array(
                store.panePresentationAtom.zoomCompanionsBySourcePaneId.keys
            )
        )
        store.panePresentationAtom.clearAllZoomRuntimeState()
    }

    func updateZoomCompanionOwnership(
        forSourcePane sourcePaneId: UUID,
        capturedCompanion: ZoomCompanionMetadata?,
        owningTabId: UUID
    ) {
        guard let capturedCompanion else { return }
        store.panePresentationAtom.reassociateZoomCompanion(
            capturedCompanion,
            forSourcePane: sourcePaneId,
            to: owningTabId
        )
        refreshBridgePaneActivities()
    }

    func captureZoomCompanions(
        forSourcePanes sourcePaneIds: some Sequence<UUID>
    ) -> [UUID: ZoomCompanionMetadata] {
        var capturedCompanions: [UUID: ZoomCompanionMetadata] = [:]
        for sourcePaneId in sourcePaneIds {
            guard
                let companion = store.panePresentationAtom.zoomCompanion(
                    forSourcePane: sourcePaneId
                )
            else {
                continue
            }
            capturedCompanions[sourcePaneId] = companion
        }
        return capturedCompanions
    }

    func reassociateZoomCompanionsWithCurrentTabs(
        _ capturedCompanions: [UUID: ZoomCompanionMetadata]
    ) {
        var didReassociateCompanion = false
        for (sourcePaneId, companion) in capturedCompanions {
            guard
                let owningTabId = store.tabLayoutAtom.tabContaining(
                    paneId: sourcePaneId
                )?.id
            else {
                continue
            }
            store.panePresentationAtom.reassociateZoomCompanion(
                companion,
                forSourcePane: sourcePaneId,
                to: owningTabId
            )
            didReassociateCompanion = true
        }
        if didReassociateCompanion {
            refreshBridgePaneActivities()
        }
    }

    @discardableResult
    func reconcileZoomCompanion(
        sourcePaneId: UUID,
        owningTabId: UUID
    ) -> ZoomViewerPresentation {
        reconcileZoomCompanion(
            sourcePaneId: sourcePaneId,
            owningTabId: owningTabId,
            viewerSurfaceRequest: requestBridgePaneSurface
        )
    }

    @discardableResult
    func reconcileZoomCompanion(
        sourcePaneId: UUID,
        owningTabId: UUID,
        viewerSurfaceRequest: @MainActor (BridgeProductSurface, UUID) -> Bool
    ) -> ZoomViewerPresentation {
        guard
            let context = zoomCompanionContext(
                sourcePaneId: sourcePaneId,
                owningTabId: owningTabId
            )
        else {
            retireLostZoomCompanion(
                forSourcePane: sourcePaneId,
                viewerWorktreeStillResolves: false
            )
            return .unavailable
        }

        if store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePaneId) != nil {
            if let retained = retainedZoomCompanionPresentation(
                sourcePaneId: sourcePaneId,
                owningTabId: owningTabId,
                resolvedWorktreeId: context.worktree.id
            ) {
                return retained
            }
            retireLostZoomCompanion(
                forSourcePane: sourcePaneId,
                viewerWorktreeStillResolves: true
            )
            return .retryable
        }

        let companionPaneId = UUIDv7.generate()
        let companionState = BridgePaneState(
            panelKind: .fileViewer,
            source: .workspace(
                rootPath: context.worktree.path.path,
                baseline: .localDefaultBranch(branchName: "main")
            )
        )
        let companionPane = Pane(
            id: companionPaneId,
            content: .bridgePanel(companionState),
            metadata: PaneMetadata(
                contentType: .diff,
                launchDirectory: context.worktree.path,
                title: "Files",
                facets: PaneContextFacets(
                    repoId: context.repo.id,
                    repoName: context.repo.name,
                    worktreeId: context.worktree.id,
                    worktreeName: context.worktree.name,
                    cwd: context.sourcePane.metadata.cwd ?? context.worktree.path
                )
            )
        )

        viewRegistry.ensureSlot(for: companionPaneId)
        _ = createBridgePaneView(for: companionPane, state: companionState)
        guard viewerSurfaceRequest(.file, companionPaneId) else {
            teardownView(for: companionPaneId)
            retireBridgePaneActivityAuthority(for: companionPaneId)
            viewRegistry.retireSlot(for: companionPaneId)
            store.panePresentationAtom.markZoomCompanionLost(
                forSourcePane: sourcePaneId,
                viewerWorktreeStillResolves: true
            )
            return .retryable
        }

        store.panePresentationAtom.cacheZoomCompanion(
            ZoomCompanionMetadata(
                owningTabId: owningTabId,
                resolvedWorktreeId: context.worktree.id,
                companionPaneId: companionPaneId,
                lastZoomVisibility: .visible
            ),
            forSourcePane: sourcePaneId
        )
        refreshBridgePaneActivities()
        return .retainedVisible(companionPaneId: companionPaneId)
    }

    private func retainedZoomCompanionPresentation(
        sourcePaneId: UUID,
        owningTabId: UUID,
        resolvedWorktreeId: UUID
    ) -> ZoomViewerPresentation? {
        guard
            let companion = store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePaneId),
            companion.owningTabId == owningTabId,
            companion.resolvedWorktreeId == resolvedWorktreeId,
            viewRegistry.allBridgeViews[companion.companionPaneId] != nil,
            runtimeForPane(PaneId(existingUUID: companion.companionPaneId)) is BridgeRuntime,
            let presentation = store.panePresentationAtom.zoomPresentation(forTab: owningTabId),
            presentation.sourcePaneId == sourcePaneId,
            presentation.viewerPresentation.companionPaneId == companion.companionPaneId
        else {
            return nil
        }
        refreshBridgePaneActivities()
        return presentation.viewerPresentation
    }

    private func zoomCompanionContext(
        sourcePaneId: UUID,
        owningTabId: UUID
    ) -> (sourcePane: Pane, repo: Repo, worktree: Worktree)? {
        guard
            let tab = store.tabLayoutAtom.tab(owningTabId),
            tab.allPaneIds.contains(sourcePaneId),
            let sourcePane = store.paneAtom.pane(sourcePaneId),
            sourcePane.parentPaneId == nil
        else {
            return nil
        }

        if let worktreeId = sourcePane.worktreeId {
            guard
                let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                let repo = store.repositoryTopologyAtom.repo(containing: worktreeId)
            else {
                return nil
            }
            return (sourcePane, repo, worktree)
        }
        if let resolved = store.repositoryTopologyAtom.repoAndWorktree(
            containing: sourcePane.metadata.cwd
        ) {
            return (sourcePane, resolved.repo, resolved.worktree)
        }

        let registeredWorktreeContexts = store.repositoryTopologyAtom.repos.flatMap { repo in
            repo.worktrees.map { worktree in
                (repo: repo, worktree: worktree)
            }
        }
        guard registeredWorktreeContexts.count == 1,
            let onlyRegisteredContext = registeredWorktreeContexts.first
        else {
            return nil
        }
        return (
            sourcePane,
            onlyRegisteredContext.repo,
            onlyRegisteredContext.worktree
        )
    }
}
