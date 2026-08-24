import AgentStudioCore
import Foundation
import Observation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func bindPullRequestDemand(toOwningWindowId windowId: UUID) {
        repositoryFactDemandOwningWindowId = windowId
        restartRepositoryFactDemandObservation()
    }

    func stopRepositoryFactDemandObservation() {
        repositoryFactDemandObservationGeneration &+= 1
    }

    func settleRepositoryFactDemandAdmissionForPerformanceProof() async {
        repositoryFactDemandCoordinator.accept(captureRepositoryFactDemandSnapshot())
        await repositoryFactDemandCoordinator.waitUntilIdle()
        await filesystemSource.waitForRepositoryFactDemandAdmission()
    }

    private func restartRepositoryFactDemandObservation() {
        repositoryFactDemandObservationGeneration &+= 1
        observeRepositoryFactDemand(generation: repositoryFactDemandObservationGeneration)
    }

    private func observeRepositoryFactDemand(generation: UInt64) {
        let snapshot = withObservationTracking {
            captureRepositoryFactDemandSnapshot()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self,
                    self.repositoryFactDemandObservationGeneration == generation
                else { return }
                self.observeRepositoryFactDemand(generation: generation)
            }
        }
        repositoryFactDemandCoordinator.accept(snapshot)
    }

    private func captureRepositoryFactDemandSnapshot() -> RepositoryFactDemandSnapshot {
        let paneGraph = store.paneAtom.graphAtom
        let topology = store.repositoryTopologyAtom
        let associationByPaneId = Dictionary(
            uniqueKeysWithValues: paneGraph.repositoryAssociationPaneIds.compactMap { paneId in
                paneGraph.repositoryAssociation(for: paneId).map { (paneId, $0) }
            }
        )
        let membershipWorktreeIds = topology.repositoryMembershipWorktreeIds
        let repositoryIdByWorktreeId = Dictionary(
            uniqueKeysWithValues: membershipWorktreeIds.compactMap { worktreeId in
                topology.repositoryId(containing: worktreeId).map { (worktreeId, $0) }
            }
        )
        let windowPresentation = repositoryFactDemandWindowPresentation()
        let sidebarIsAttended =
            windowPresentation == .visible
            && !atom(\.workspaceSidebarState).sidebarCollapsed
        let activePaneWorktreeId = store.tabLayoutAtom.activeTab?.activePaneId
            .flatMap { associationByPaneId[$0]?.worktreeId }

        return RepositoryFactDemandSnapshot(
            activePaneWorktreeId: activePaneWorktreeId,
            sidebarAttendedWorktreeIds: sidebarIsAttended ? membershipWorktreeIds : [],
            visibleActiveTabWorktreeIds: visibleActiveTabWorktreeIds(
                windowPresentation: windowPresentation,
                associationByPaneId: associationByPaneId
            ),
            openWorktreeIds: Set(associationByPaneId.values.compactMap(\.worktreeId)),
            repositoryIdByWorktreeId: repositoryIdByWorktreeId
        )
    }

    private func repositoryFactDemandWindowPresentation() -> PullRequestDemandProjection.WindowPresentation {
        let windowFacts =
            repositoryFactDemandOwningWindowId
            .flatMap(windowLifecycleStore.presentationFacts(for:))
            ?? .hidden
        if !windowFacts.isVisible { return .hidden }
        if windowFacts.isMiniaturized { return .miniaturized }
        if windowFacts.isOccluded { return .occluded }
        return .visible
    }

    private func visibleActiveTabWorktreeIds(
        windowPresentation: PullRequestDemandProjection.WindowPresentation,
        associationByPaneId: [UUID: PaneRepositoryAssociation]
    ) -> Set<UUID> {
        guard let activeTab = store.tabLayoutAtom.activeTab else { return [] }
        let activeLayoutPaneIds = Set(activeTab.activeArrangement.layout.paneIds)
        var relevantPaneIds = activeLayoutPaneIds
        let expandedDrawerProjection: (UUID) -> PullRequestDemandProjection.ExpandedDrawer? = { parentPaneId in
            guard self.store.paneAtom.isDrawerExpanded(for: parentPaneId),
                let drawerView = self.arrangementView.drawerView(forParent: parentPaneId)
            else { return nil }
            relevantPaneIds.formUnion(drawerView.layout.paneIds)
            return PullRequestDemandProjection.ExpandedDrawer(
                parentPaneId: parentPaneId,
                paneIds: Set(drawerView.layout.paneIds),
                minimizedPaneIds: drawerView.minimizedPaneIds
            )
        }
        let expandedDrawers = activeLayoutPaneIds.compactMap(expandedDrawerProjection)
        let expandedDrawer = expandedDrawers.first
        let zoom = store.panePresentationAtom.zoomPresentation(forTab: activeTab.id).map { presentation in
            let companionWorktreeId: UUID? = {
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
                visibleCompanionWorktreeId: companionWorktreeId
            )
        }
        let worktreeIdByPaneId = Dictionary(
            uniqueKeysWithValues: relevantPaneIds.compactMap { paneId in
                associationByPaneId[paneId]?.worktreeId.map { (paneId, $0) }
            }
        )
        return PullRequestDemandProjection.worktreeIds(
            from: .init(
                windowPresentation: windowPresentation,
                sidebarWorktreeIds: [],
                activeLayoutPaneIds: activeLayoutPaneIds,
                minimizedLayoutPaneIds: activeTab.activeArrangement.minimizedPaneIds,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                expandedDrawer: expandedDrawer,
                zoom: zoom,
                worktreeIdByPaneId: worktreeIdByPaneId
            )
        )
    }
}
