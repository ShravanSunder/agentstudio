import AgentStudioCore
import Foundation
import Observation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func bindPullRequestDemand(toOwningWindowId windowId: UUID) {
        pullRequestDemandOwningWindowId = windowId
        restartPullRequestDemandObservation()
    }

    private func restartPullRequestDemandObservation() {
        pullRequestDemandObservationGeneration &+= 1
        observePullRequestDemand(generation: pullRequestDemandObservationGeneration)
    }

    private func observePullRequestDemand(generation: UInt64) {
        let worktreeIds = withObservationTracking {
            capturePullRequestDemandWorktreeIds()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self,
                    self.pullRequestDemandObservationGeneration == generation
                else { return }
                self.observePullRequestDemand(generation: generation)
            }
        }
        schedulePullRequestDemandDelivery(worktreeIds)
    }

    private func capturePullRequestDemandWorktreeIds() -> Set<UUID> {
        let windowFacts =
            pullRequestDemandOwningWindowId
            .flatMap(windowLifecycleStore.presentationFacts(for:))
            ?? .hidden
        let windowPresentation: PullRequestDemandProjection.WindowPresentation =
            if !windowFacts.isVisible {
                .hidden
            } else if windowFacts.isMiniaturized {
                .miniaturized
            } else if windowFacts.isOccluded {
                .occluded
            } else {
                .visible
            }

        guard let activeTab = store.tabLayoutAtom.activeTab else {
            return PullRequestDemandProjection.worktreeIds(
                from: .init(
                    windowPresentation: windowPresentation,
                    sidebarWorktreeIds: atom(\.sidebarVisibleWorktreesRuntime).visibleWorktreeIds,
                    activeLayoutPaneIds: [],
                    minimizedLayoutPaneIds: [],
                    isManagementLayerActive: atom(\.managementLayer).isActive,
                    expandedDrawer: nil,
                    zoom: nil,
                    worktreeIdByPaneId: [:]
                )
            )
        }

        let activeLayoutPaneIds = Set(activeTab.activeArrangement.layout.paneIds)
        var paneIds = activeLayoutPaneIds
        let expandedDrawers: [PullRequestDemandProjection.ExpandedDrawer] =
            activeLayoutPaneIds.compactMap { parentPaneId in
                guard store.paneAtom.isDrawerExpanded(for: parentPaneId),
                    let drawerView = arrangementView.drawerView(forParent: parentPaneId)
                else { return nil }
                paneIds.formUnion(drawerView.layout.paneIds)
                return .init(
                    parentPaneId: parentPaneId,
                    paneIds: Set(drawerView.layout.paneIds),
                    minimizedPaneIds: drawerView.minimizedPaneIds
                )
            }
        let expandedDrawer = expandedDrawers.first

        let zoomPresentation = store.panePresentationAtom.zoomPresentation(forTab: activeTab.id)
        let zoom = zoomPresentation.map { presentation in
            let visibleCompanionWorktreeId: UUID? = {
                guard case .retainedVisible(let companionPaneId) = presentation.viewerPresentation,
                    let companion = store.panePresentationAtom.zoomCompanion(
                        forSourcePane: presentation.sourcePaneId
                    ),
                    companion.owningTabId == activeTab.id,
                    companion.companionPaneId == companionPaneId
                else { return nil }
                return companion.resolvedWorktreeId
            }()
            return PullRequestDemandProjection.Zoom(
                sourcePaneId: presentation.sourcePaneId,
                visibleCompanionWorktreeId: visibleCompanionWorktreeId
            )
        }

        let worktreeIdByPaneId = Dictionary(
            uniqueKeysWithValues: paneIds.compactMap { paneId in
                store.paneAtom.pane(paneId)?.worktreeId.map { (paneId, $0) }
            })
        return PullRequestDemandProjection.worktreeIds(
            from: .init(
                windowPresentation: windowPresentation,
                sidebarWorktreeIds: atom(\.sidebarVisibleWorktreesRuntime).visibleWorktreeIds,
                activeLayoutPaneIds: activeLayoutPaneIds,
                minimizedLayoutPaneIds: activeTab.activeArrangement.minimizedPaneIds,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                expandedDrawer: expandedDrawer,
                zoom: zoom,
                worktreeIdByPaneId: worktreeIdByPaneId
            )
        )
    }

    private func schedulePullRequestDemandDelivery(_ worktreeIds: Set<UUID>) {
        guard worktreeIds != pendingPullRequestDemandWorktreeIds else { return }
        pendingPullRequestDemandWorktreeIds = worktreeIds
        guard pullRequestDemandDeliveryTask == nil else { return }
        guard worktreeIds != lastDeliveredPullRequestDemandWorktreeIds else {
            pendingPullRequestDemandWorktreeIds = nil
            return
        }

        pullRequestDemandDeliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let nextWorktreeIds = self.pendingPullRequestDemandWorktreeIds {
                self.pendingPullRequestDemandWorktreeIds = nil
                guard nextWorktreeIds != self.lastDeliveredPullRequestDemandWorktreeIds else { continue }
                self.pullRequestDemandInFlightWorktreeIds = nextWorktreeIds
                await self.filesystemSource.setPullRequestDemandWorktrees(nextWorktreeIds)
                guard !Task.isCancelled else { return }
                self.lastDeliveredPullRequestDemandWorktreeIds = nextWorktreeIds
                self.pullRequestDemandInFlightWorktreeIds = nil
            }
            self.pullRequestDemandDeliveryTask = nil
        }
    }
}
