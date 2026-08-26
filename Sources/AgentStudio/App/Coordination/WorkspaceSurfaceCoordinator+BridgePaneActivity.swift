import AgentStudioBridge
import AgentStudioCore
import Foundation
import Observation

@MainActor
extension WorkspaceSurfaceCoordinator {
    private struct BridgePaneActivityInput {
        let paneId: UUID
        let resolvedWorktree: Worktree?
        let facts: BridgePaneActivityFacts
    }

    private struct WorkspaceActivityFacts {
        let isInActiveTab: Bool
        let isInActiveArrangement: Bool
        let isInExpandedDrawer: Bool
        let isMinimized: Bool
        let isZoomExcluded: Bool
    }

    func bindBridgePaneActivities(toOwningWindowId windowId: UUID) {
        bridgePaneActivityOwningWindowId = windowId
        restartBridgePaneActivityObservation()
    }

    func bridgePaneActivity(for paneId: UUID) -> BridgePaneActivity? {
        bridgePaneActivityCoordinatorsByPaneId[paneId]?.activity
    }

    func bridgePaneActivityAuthorityIdentity(for paneId: UUID) -> ObjectIdentifier? {
        bridgePaneActivityCoordinatorsByPaneId[paneId].map(ObjectIdentifier.init)
    }

    func ensureBridgePaneActivityAuthority(for paneId: UUID) {
        guard bridgePaneActivityCoordinatorsByPaneId[paneId] == nil else { return }
        bridgePaneActivityCoordinatorsByPaneId[paneId] = BridgePaneActivityCoordinator()
    }

    func closeBridgePaneActivityAuthority(for paneId: UUID) {
        guard bridgePaneActivityCoordinatorsByPaneId[paneId] != nil else { return }
        bridgePaneActivityCoordinatorsByPaneId[paneId]?.close()
        removeBridgeGitReadActivity(for: paneId)
        viewRegistry.allBridgeViews[paneId]?.controller.applyBridgePaneActivity(.closed)
    }

    func retireBridgePaneActivityAuthority(for paneId: UUID) {
        closeBridgePaneActivityAuthority(for: paneId)
        bridgePaneActivityCoordinatorsByPaneId.removeValue(forKey: paneId)
    }

    func closeAllBridgePaneActivityAuthorities() {
        for (paneId, coordinator) in bridgePaneActivityCoordinatorsByPaneId {
            coordinator.close()
            removeBridgeGitReadActivity(for: paneId)
        }
    }

    func replaceClosedBridgePaneActivityAuthorityForUndo(paneId: UUID) {
        guard bridgePaneActivityCoordinatorsByPaneId[paneId]?.activity == .closed else {
            ensureBridgePaneActivityAuthority(for: paneId)
            return
        }
        bridgePaneActivityCoordinatorsByPaneId[paneId] = BridgePaneActivityCoordinator()
        refreshBridgePaneActivities()
    }

    func startBridgePaneActivityObservation() {
        restartBridgePaneActivityObservation()
    }

    func refreshBridgePaneActivities() {
        applyBridgePaneActivityInputs(captureBridgePaneActivityInputs())
    }

    private func restartBridgePaneActivityObservation() {
        bridgePaneActivityObservationGeneration &+= 1
        observeBridgePaneActivityInputs(generation: bridgePaneActivityObservationGeneration)
    }

    private func observeBridgePaneActivityInputs(generation: UInt64) {
        let inputs = withObservationTracking {
            captureBridgePaneActivityInputs()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self,
                    self.bridgePaneActivityObservationGeneration == generation
                else { return }
                self.observeBridgePaneActivityInputs(generation: generation)
            }
        }
        applyBridgePaneActivityInputs(inputs)
    }

    private func captureBridgePaneActivityInputs() -> [BridgePaneActivityInput] {
        let paneGraph = store.paneAtom.graphAtom
        let bridgePaneFacts: [PaneStructuralFacts] = paneGraph.paneIDs.compactMap { paneID in
            guard let paneFacts = paneGraph.paneStructuralFacts(paneID), paneFacts.isBridgeEligible else {
                return nil
            }
            return paneFacts
        }
        let windowPresentationFacts =
            bridgePaneActivityOwningWindowId
            .flatMap(windowLifecycleStore.presentationFacts(for:))
            ?? .hidden

        let durableInputs = bridgePaneFacts.map { paneFacts in
            let workspaceFacts = workspaceActivityFacts(for: paneFacts)
            let isControllerInstalled =
                viewRegistry.allBridgeViews[paneFacts.paneID] != nil
                && bridgePaneRetirementTasksByPaneId[paneFacts.paneID] == nil
            return BridgePaneActivityInput(
                paneId: paneFacts.paneID,
                resolvedWorktree: store.repositoryTopologyAtom.validatedAssociation(
                    repoId: paneFacts.repoID,
                    worktreeId: paneFacts.worktreeID
                )?.worktree,
                facts: BridgePaneActivityFacts(
                    residency: paneFacts.residency,
                    isControllerInstalled: isControllerInstalled,
                    isInActiveTab: workspaceFacts.isInActiveTab,
                    isInActiveArrangement: workspaceFacts.isInActiveArrangement,
                    isInExpandedDrawer: workspaceFacts.isInExpandedDrawer,
                    isMinimized: workspaceFacts.isMinimized,
                    isZoomExcluded: workspaceFacts.isZoomExcluded,
                    isOwningWindowVisible: windowPresentationFacts.isVisible,
                    isOwningWindowMiniaturized: windowPresentationFacts.isMiniaturized,
                    isOwningWindowOccluded: windowPresentationFacts.isOccluded,
                    isAuthorityClosed: false
                )
            )
        }

        let activeTabId = store.tabLayoutAtom.activeTabId
        let zoomCompanions = store.panePresentationAtom.zoomCompanionsBySourcePaneId
        let companionInputs: [BridgePaneActivityInput] =
            zoomCompanions.compactMap { sourcePaneId, companion in
                guard let resolvedWorktree = store.repositoryTopologyAtom.worktree(companion.resolvedWorktreeId)
                else {
                    return nil
                }
                let zoomPresentation = store.panePresentationAtom.zoomPresentation(
                    forTab: companion.owningTabId
                )
                let isVisibleZoom =
                    zoomPresentation?.sourcePaneId == sourcePaneId
                    && zoomPresentation?.viewerPresentation
                        == .retainedVisible(companionPaneId: companion.companionPaneId)
                let isInActiveTab = activeTabId == companion.owningTabId
                let isControllerInstalled =
                    viewRegistry.allBridgeViews[companion.companionPaneId] != nil
                    && bridgePaneRetirementTasksByPaneId[companion.companionPaneId] == nil
                return BridgePaneActivityInput(
                    paneId: companion.companionPaneId,
                    resolvedWorktree: resolvedWorktree,
                    facts: BridgePaneActivityFacts(
                        residency: .active,
                        isControllerInstalled: isControllerInstalled,
                        isInActiveTab: isInActiveTab,
                        isInActiveArrangement: isInActiveTab && isVisibleZoom,
                        isInExpandedDrawer: false,
                        isMinimized: false,
                        isZoomExcluded: !isVisibleZoom,
                        isOwningWindowVisible: windowPresentationFacts.isVisible,
                        isOwningWindowMiniaturized: windowPresentationFacts.isMiniaturized,
                        isOwningWindowOccluded: windowPresentationFacts.isOccluded,
                        isAuthorityClosed: false
                    )
                )
            }
        return durableInputs + companionInputs
    }

    private func applyBridgePaneActivityInputs(_ inputs: [BridgePaneActivityInput]) {
        for input in inputs {
            ensureBridgePaneActivityAuthority(for: input.paneId)
            guard let activityCoordinator = bridgePaneActivityCoordinatorsByPaneId[input.paneId]
            else { continue }
            let activity = activityCoordinator.update(from: input.facts)
            updateBridgeGitReadActivity(
                for: input.paneId,
                resolvedWorktree: input.resolvedWorktree,
                activity: activity
            )
            viewRegistry.allBridgeViews[input.paneId]?.controller.applyBridgePaneActivity(activity)
        }
    }

    private func updateBridgeGitReadActivity(
        for paneId: UUID,
        resolvedWorktree: Worktree?,
        activity: BridgePaneActivity
    ) {
        guard activity != .closed,
            let resolvedWorktree
        else {
            removeBridgeGitReadActivity(for: paneId)
            return
        }
        let rank: BridgeGitReadActivityRank =
            switch activity {
            case .foreground:
                .foreground
            case .loadedHidden:
                .loadedHidden
            case .dormant:
                .dormant
            case .closed:
                .unranked
            }
        let precedingPropagation = bridgeGitReadActivityPropagationTask
        let scheduler = bridgeGitReadScheduler
        bridgeGitReadActivityPropagationTask = Task {
            await precedingPropagation?.value
            await scheduler.updatePaneActivity(
                paneKey: BridgeGitReadPaneKey(token: paneId.uuidString),
                worktreeKey: BridgeGitReadWorktreeKey(token: resolvedWorktree.stableKey),
                rank: rank
            )
        }
    }

    private func removeBridgeGitReadActivity(for paneId: UUID) {
        let precedingPropagation = bridgeGitReadActivityPropagationTask
        let scheduler = bridgeGitReadScheduler
        bridgeGitReadActivityPropagationTask = Task {
            await precedingPropagation?.value
            await scheduler.removePaneActivity(
                paneKey: BridgeGitReadPaneKey(token: paneId.uuidString)
            )
        }
    }

    func drainBridgeGitReadActivityPropagation() async {
        await bridgeGitReadActivityPropagationTask?.value
    }

    private func workspaceActivityFacts(for paneFacts: PaneStructuralFacts) -> WorkspaceActivityFacts {
        guard let activeTab = store.tabLayoutAtom.activeTab else {
            return WorkspaceActivityFacts(
                isInActiveTab: false,
                isInActiveArrangement: false,
                isInExpandedDrawer: false,
                isMinimized: false,
                isZoomExcluded: false
            )
        }

        let owningLayoutPaneId = paneFacts.parentPaneID ?? paneFacts.paneID
        let owningTabId = store.tabLayoutAtom.tabContaining(paneId: owningLayoutPaneId)?.id
        let isInActiveTab = owningTabId == activeTab.id
        let isInActiveArrangement =
            isInActiveTab
            && !paneFacts.isDrawerChild
            && activeTab.activePaneIds.contains(paneFacts.paneID)
        let sourcePaneId = store.panePresentationAtom.zoomPresentation(forTab: activeTab.id)?.sourcePaneId

        var isInExpandedDrawer = false
        var isMinimized = false
        if let parentPaneId = paneFacts.parentPaneID,
            isInActiveTab,
            activeTab.activePaneIds.contains(parentPaneId),
            store.paneAtom.isDrawerExpanded(for: parentPaneId),
            let drawerView = arrangementView.drawerView(forParent: parentPaneId)
        {
            isInExpandedDrawer = drawerView.layout.contains(paneFacts.paneID)
            isMinimized = drawerView.minimizedPaneIds.contains(paneFacts.paneID)
        } else if !paneFacts.isDrawerChild {
            isMinimized = activeTab.activeMinimizedPaneIds.contains(paneFacts.paneID)
        }
        if sourcePaneId == paneFacts.paneID {
            isMinimized = false
        }

        let isZoomExcluded = sourcePaneId.map { $0 != owningLayoutPaneId } ?? false
        return WorkspaceActivityFacts(
            isInActiveTab: isInActiveTab,
            isInActiveArrangement: isInActiveArrangement,
            isInExpandedDrawer: isInExpandedDrawer,
            isMinimized: isMinimized,
            isZoomExcluded: isZoomExcluded
        )
    }
}
