import AgentStudioBridge
import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func retireZoomCompanion(forSourcePane sourcePaneId: UUID) {
        let companion = store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePaneId
        )
        zoomCompanionContinuityBySourcePaneId.removeValue(forKey: sourcePaneId)
        store.panePresentationAtom.removeZoomSourcePane(sourcePaneId)
        guard let companion else { return }
        retireZoomCompanionResources(companion)
        refreshBridgePaneActivities()
    }

    private func retireLostZoomCompanion(
        forSourcePane sourcePaneId: UUID,
        viewerWorktreeStillResolves: Bool
    ) {
        retainZoomCompanionContinuity(forSourcePane: sourcePaneId)
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
            viewerWorktreeStillResolves: resolvedContext != nil
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
        zoomCompanionContinuityBySourcePaneId.removeAll()
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
        let continuity =
            retainZoomCompanionContinuity(forSourcePane: sourcePaneId)
            ?? ZoomCompanionContinuity(surface: .file, visibility: .visible)
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
            if continuity.visibility == .visible {
                _ = store.panePresentationAtom.setZoomViewerVisible(
                    true,
                    forSourcePane: sourcePaneId
                )
                return .unavailableVisible
            }
            return .unavailable
        }

        // The receiver and its record outlive the companion: CWD only injects
        // and protects a member, it never selects what the companion shows.
        let receiver = BridgeReceiver.terminal(sourcePaneId)
        let knownCWDWorktreeId = context.association?.worktree.id
        bridgeNavigationCommandHandler.ensureRecord(
            for: receiver,
            seedingKnownWorktreeId: knownCWDWorktreeId
        )
        bridgeNavigationCommandHandler.applyKnownCWDAssociation(
            knownCWDWorktreeId,
            forTerminalPane: sourcePaneId
        )
        let reviewBinding = bridgeNavigationCommandHandler.reviewBinding(for: receiver)

        if let companion = store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePaneId) {
            if let retained = retainedZoomCompanionPresentation(
                sourcePaneId: sourcePaneId,
                owningTabId: owningTabId,
                reviewWorktreeId: reviewBinding?.worktreeId
            ) {
                if let files = bridgeNavigationCommandHandler.filesBinding(for: receiver) {
                    viewRegistry.allBridgeViews[companion.companionPaneId]?.controller
                        .enqueueFilesSourceUpdate(files)
                }
                return retained
            }
            retireLostZoomCompanion(
                forSourcePane: sourcePaneId,
                viewerWorktreeStillResolves: true
            )
        }

        // The companion describes what its receiver's record reads, not the
        // terminal's latest CWD association.
        let displayed = reviewBinding.flatMap { binding in
            store.repositoryTopologyAtom.repositoryId(containing: binding.worktreeId).flatMap {
                store.repositoryTopologyAtom.validatedAssociation(repoId: $0, worktreeId: binding.worktreeId)
            }
        }
        let companionPaneId = UUIDv7.generate()
        let companionState = BridgePaneState(panelKind: .fileViewer)
        let companionPane = Pane(
            id: companionPaneId,
            content: .bridgePanel(companionState),
            metadata: Self.zoomCompanionMetadata(
                displayed: displayed,
                sourcePaneCWD: context.sourcePane.metadata.cwd
            )
        )

        viewRegistry.ensureSlot(for: companionPaneId)
        _ = createBridgePaneView(for: companionPane, state: companionState, receiver: receiver)
        guard viewerSurfaceRequest(continuity.surface, companionPaneId) else {
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
                reviewWorktreeId: reviewBinding?.worktreeId,
                companionPaneId: companionPaneId,
                lastZoomVisibility: continuity.visibility
            ),
            forSourcePane: sourcePaneId
        )
        zoomCompanionContinuityBySourcePaneId[sourcePaneId] = continuity
        refreshBridgePaneActivities()
        switch continuity.visibility {
        case .hidden:
            return .retainedHidden(companionPaneId: companionPaneId)
        case .visible:
            return .retainedVisible(companionPaneId: companionPaneId)
        }
    }

    private func retainedZoomCompanionPresentation(
        sourcePaneId: UUID,
        owningTabId: UUID,
        reviewWorktreeId: UUID?
    ) -> ZoomViewerPresentation? {
        guard
            let companion = store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePaneId),
            companion.owningTabId == owningTabId,
            companion.reviewWorktreeId == reviewWorktreeId,
            viewRegistry.allBridgeViews[companion.companionPaneId] != nil,
            runtimeForPane(PaneId(existingUUID: companion.companionPaneId)) is BridgeRuntime
        else {
            return nil
        }
        store.panePresentationAtom.cacheZoomCompanion(
            companion,
            forSourcePane: sourcePaneId
        )
        refreshBridgePaneActivities()
        switch companion.lastZoomVisibility {
        case .hidden:
            return .retainedHidden(companionPaneId: companion.companionPaneId)
        case .visible:
            return .retainedVisible(companionPaneId: companion.companionPaneId)
        }
    }

    /// The source pane of a Zoom companion and its current known-worktree
    /// association, which is nil for a terminal outside every known worktree.
    /// A receiver does not need a worktree to exist.
    private func zoomCompanionContext(
        sourcePaneId: UUID,
        owningTabId: UUID
    ) -> (sourcePane: Pane, association: (repo: Repo, worktree: Worktree)?)? {
        guard
            let tab = store.tabLayoutAtom.tab(owningTabId),
            tab.allPaneIds.contains(sourcePaneId),
            let sourcePane = store.paneAtom.pane(sourcePaneId),
            sourcePane.parentPaneId == nil
        else {
            return nil
        }
        let association = store.repositoryTopologyAtom.validatedAssociation(
            repoId: sourcePane.repoId,
            worktreeId: sourcePane.worktreeId
        )
        return (sourcePane, association.map { (repo: $0.repo, worktree: $0.worktree) })
    }

    private static func zoomCompanionMetadata(
        displayed: (repo: Repo, worktree: Worktree)?,
        sourcePaneCWD: URL?
    ) -> PaneMetadata {
        guard let displayed else {
            return PaneMetadata(
                contentType: .diff,
                launchDirectory: sourcePaneCWD,
                title: "Files",
                facets: PaneContextFacets(cwd: sourcePaneCWD)
            )
        }
        return PaneMetadata(
            contentType: .diff,
            launchDirectory: displayed.worktree.path,
            title: "Files",
            facets: PaneContextFacets(
                repoId: displayed.repo.id,
                repoName: displayed.repo.name,
                worktreeId: displayed.worktree.id,
                worktreeName: displayed.worktree.name,
                cwd: displayed.worktree.path
            )
        )
    }

    func reconcileZoomCompanionAfterCWDChange(sourcePaneId: UUID) {
        let hasZoomRuntime =
            store.panePresentationAtom.zoomCompanion(forSourcePane: sourcePaneId) != nil
            || zoomCompanionContinuityBySourcePaneId[sourcePaneId] != nil
            || store.panePresentationAtom.zoomPresentationsByTabId.values.contains {
                $0.sourcePaneId == sourcePaneId
            }
        guard hasZoomRuntime,
            let owningTabId = store.tabLayoutAtom.tabContaining(paneId: sourcePaneId)?.id
        else {
            return
        }
        reconcileZoomCompanion(
            sourcePaneId: sourcePaneId,
            owningTabId: owningTabId
        )
    }

    @discardableResult
    private func retainZoomCompanionContinuity(
        forSourcePane sourcePaneId: UUID
    ) -> ZoomCompanionContinuity? {
        if let companion = store.panePresentationAtom.zoomCompanion(
            forSourcePane: sourcePaneId
        ) {
            let retainedSurface =
                viewRegistry.allBridgeViews[companion.companionPaneId]?.controller
                .retainedViewerSurface
                ?? zoomCompanionContinuityBySourcePaneId[sourcePaneId]?.surface
                ?? .file
            let continuity = ZoomCompanionContinuity(
                surface: retainedSurface,
                visibility: companion.lastZoomVisibility
            )
            zoomCompanionContinuityBySourcePaneId[sourcePaneId] = continuity
            return continuity
        }
        if let continuity = zoomCompanionContinuityBySourcePaneId[sourcePaneId] {
            return continuity
        }
        guard
            let viewerPresentation = store.panePresentationAtom.zoomPresentationsByTabId.values
                .first(where: { $0.sourcePaneId == sourcePaneId })?
                .viewerPresentation
        else {
            return nil
        }
        let visibility: ZoomViewerVisibility =
            switch viewerPresentation {
            case .unavailable, .retainedHidden:
                .hidden
            case .unavailableVisible, .retryable, .retainedVisible:
                .visible
            }
        let continuity = ZoomCompanionContinuity(
            surface: .file,
            visibility: visibility
        )
        zoomCompanionContinuityBySourcePaneId[sourcePaneId] = continuity
        return continuity
    }
}
