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
        repositoryFactDemandCoordinator.accept(captureRepositoryFactDemandInput())
        await repositoryFactDemandCoordinator.waitUntilIdle()
        await filesystemSource.waitForRepositoryFactDemandAdmission()
    }

    func gitLogicalDebtSnapshotForPerformanceProof() async -> GitLogicalDebtSnapshot? {
        guard let pipeline = filesystemSource as? FilesystemGitPipeline else { return nil }
        return await pipeline.gitLogicalDebtSnapshot()
    }

    private func restartRepositoryFactDemandObservation() {
        repositoryFactDemandObservationGeneration &+= 1
        observeRepositoryFactDemand(generation: repositoryFactDemandObservationGeneration)
    }

    private func observeRepositoryFactDemand(generation: UInt64) {
        let input = withObservationTracking {
            captureRepositoryFactDemandInput()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self,
                    self.repositoryFactDemandObservationGeneration == generation
                else { return }
                self.observeRepositoryFactDemand(generation: generation)
            }
        }
        repositoryFactDemandCoordinator.accept(input)
    }

    private func captureRepositoryFactDemandInput() -> RepositoryFactDemandInput {
        let paneGraph = store.paneAtom.graphAtom
        let topology = store.repositoryTopologyAtom
        let repositoryLocalActivity = atom(\.repositoryLocalActivity)
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
        let repositoryIDs = topology.repositoryIdsInOrder
        var worktreeStableKeysByRepositoryID: [UUID: [UUID: String]] = [:]
        for worktreeID in membershipWorktreeIds {
            guard
                let repositoryID = repositoryIdByWorktreeId[worktreeID],
                let worktreeStableKey = topology.worktreeStableKey(for: worktreeID)
            else { continue }
            worktreeStableKeysByRepositoryID[repositoryID, default: [:]][worktreeID] = worktreeStableKey
        }
        let activityTopology: [RepositoryActivityTopology] = repositoryIDs.compactMap { repositoryID in
            guard let repositoryStableKey = topology.repositoryStableKey(for: repositoryID) else { return nil }
            return RepositoryActivityTopology(
                repositoryID: repositoryID,
                repositoryStableKey: repositoryStableKey,
                worktreeStableKeysByID: worktreeStableKeysByRepositoryID[repositoryID] ?? [:]
            )
        }
        let repositoryLocalActivityByStableKey = Dictionary(
            uniqueKeysWithValues: activityTopology.compactMap { repository in
                repositoryLocalActivity.activity(for: repository.repositoryStableKey).map {
                    (repository.repositoryStableKey, $0)
                }
            }
        )

        return RepositoryFactDemandInput(
            activePaneWorktreeId: activePaneWorktreeId,
            sidebarAttendedWorktreeIds: sidebarIsAttended ? membershipWorktreeIds : [],
            visibleActiveTabWorktreeIds: visibleActiveTabWorktreeIds(
                windowPresentation: windowPresentation,
                associationByPaneId: associationByPaneId
            ),
            openWorktreeIds: Set(associationByPaneId.values.compactMap(\.worktreeId)),
            repositoryIdByWorktreeId: repositoryIdByWorktreeId,
            activityTopology: activityTopology,
            localActivityHydrationDisposition: repositoryLocalActivity.hydrationDisposition,
            repositoryLocalActivityByStableKey: repositoryLocalActivityByStableKey
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
