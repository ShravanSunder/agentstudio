import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation
import Observation

/// Temporary App composition snapshot for Repo Explorer command presentation.
/// It is advisory only; command execution always re-enters `AppCommandDispatcher`.
@MainActor
@Observable
final class RepoExplorerCommandPresentationBatch {
    private struct LocationCapabilityFacts: Equatable {
        let tabID: UUID
        let paneID: UUID
        let tab: Tab?
        let zoomPresentation: ZoomPresentation?
        let paneStructuralFacts: PaneStructuralFacts?
        let isDrawerExpanded: Bool?
    }

    private struct CapabilityFactsFingerprint: Equatable {
        let activeTabID: UUID?
        let isManagementLayerActive: Bool
        let locationsByWorktreeID: [UUID: [LocationCapabilityFacts]]

        func changedWorktreeIDs(
            comparedTo previous: Self,
            among worktreeIDs: Set<UUID>
        ) -> Set<UUID> {
            Set(
                worktreeIDs.filter { worktreeID in
                    locationsByWorktreeID[worktreeID] != previous.locationsByWorktreeID[worktreeID]
                })
        }

        func globalCapabilitiesMatch(_ previous: Self) -> Bool {
            activeTabID == previous.activeTabID
                && isManagementLayerActive == previous.isManagementLayerActive
        }
    }

    private(set) var snapshot = RepoExplorerCommandPresentationSnapshot.empty

    private let store: WorkspaceStore
    private let repoExplorerPrefs: RepoExplorerSidebarPrefsAtom
    private let visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom
    private let dispatcher: AppCommandDispatcher
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var lastVisibleWorktreeIDs: Set<UUID> = []
    @ObservationIgnored private var lastRequests: Set<RepoExplorerCommandPresentationRequest> = []
    @ObservationIgnored private var lastCapabilityFactsFingerprint: CapabilityFactsFingerprint?

    init(
        store: WorkspaceStore,
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom,
        dispatcher: AppCommandDispatcher,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.store = store
        self.repoExplorerPrefs = repoExplorerPrefs
        self.visibleWorktrees = visibleWorktrees
        self.dispatcher = dispatcher
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    func start() {
        let observationID = UUID()
        self.observationID = observationID
        lastVisibleWorktreeIDs = []
        lastRequests = []
        lastCapabilityFactsFingerprint = nil
        refresh(observationID: observationID)
    }

    func stop() {
        observationID = nil
    }

    private func refresh(observationID: UUID) {
        guard self.observationID == observationID else { return }
        let nextGeneration = snapshot.generation &+ 1
        let capture = withObservationTracking {
            let visibleWorktreeIDs = visibleWorktrees.visibleWorktreeIds
            return (
                visibleWorktreeIDs,
                observeApprovedCapabilityFacts(visibleWorktreeIDs: visibleWorktreeIDs),
                commandPresentationRequests(visibleWorktreeIDs: visibleWorktreeIDs)
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh(observationID: observationID)
            }
        }
        let visibleWorktreeIDs = capture.0
        let capabilityFactsFingerprint = capture.1
        let requests = capture.2
        let visibleSetDelta = visibleWorktreeIDs.symmetricDifference(lastVisibleWorktreeIDs)
        let survivingVisibleWorktreeIDs = visibleWorktreeIDs.intersection(lastVisibleWorktreeIDs)
        let previousFingerprint = lastCapabilityFactsFingerprint
        let globalCapabilitiesMatch =
            previousFingerprint.map {
                capabilityFactsFingerprint.globalCapabilitiesMatch($0)
            } ?? false
        let changedWorktreeIDs =
            previousFingerprint.map {
                capabilityFactsFingerprint.changedWorktreeIDs(
                    comparedTo: $0,
                    among: survivingVisibleWorktreeIDs
                )
            } ?? survivingVisibleWorktreeIDs
        let retainedResults = snapshot.results.filter { requests.contains($0.key) }
        let requestsToResolve: Set<RepoExplorerCommandPresentationRequest>
        if snapshot.generation == 0 || !globalCapabilitiesMatch {
            requestsToResolve = requests
        } else {
            var affectedRequests = requests.subtracting(lastRequests)
            affectedRequests.formUnion(
                worktreeCommandPresentationRequests(worktreeIDs: changedWorktreeIDs)
                    .intersection(requests)
            )
            requestsToResolve = affectedRequests
        }
        let resolvedResults =
            requestsToResolve.isEmpty
            ? [:]
            : dispatcher.repoExplorerCommandPresentationSnapshot(
                requests: requestsToResolve,
                generation: nextGeneration
            ).results
        let nextSnapshot = RepoExplorerCommandPresentationSnapshot(
            generation: nextGeneration,
            results: retainedResults.merging(resolvedResults) { _, resolved in resolved }
        )
        lastVisibleWorktreeIDs = visibleWorktreeIDs
        lastRequests = requests
        lastCapabilityFactsFingerprint = capabilityFactsFingerprint
        let reusedCount = requests.count - requestsToResolve.count
        if snapshot.results != nextSnapshot.results {
            let affectedItemCount = Self.affectedItemCount(
                previous: snapshot.results,
                next: nextSnapshot.results
            )
            if affectedItemCount == 1 {
                RepoExplorerPerformanceTelemetry.shared.record(
                    stage: "command_affected_row",
                    outcome: "changed"
                )
            } else {
                RepoExplorerPerformanceTelemetry.shared.record(
                    stage: "command_whole_surface",
                    outcome: "changed"
                )
            }
            snapshot = nextSnapshot
        }
        performanceTraceRecorder?.record(
            .repoExplorerCommandPresentation,
            attributes: [
                "agentstudio.performance.repo_explorer.visible_set.count": .int(visibleWorktreeIDs.count),
                "agentstudio.performance.repo_explorer.visible_set_delta.count": .int(visibleSetDelta.count),
                "agentstudio.performance.repo_explorer.command_resolution.count": .int(requestsToResolve.count),
                "agentstudio.performance.repo_explorer.command_reused.count": .int(reusedCount),
            ]
        )
    }

    private static func affectedItemCount(
        previous: [RepoExplorerCommandPresentationRequest: Bool],
        next: [RepoExplorerCommandPresentationRequest: Bool]
    ) -> Int {
        Set(previous.keys).union(next.keys).count { request in
            previous[request] != next[request]
        }
    }

    private func observeApprovedCapabilityFacts(
        visibleWorktreeIDs: Set<UUID>
    ) -> CapabilityFactsFingerprint {
        let activeTabID = store.tabLayoutAtom.activeTabId
        let isManagementLayerActive = atom(\.managementLayer).isActive
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let locationsByWorktreeID = atom(\.workspaceLookup).paneLocationsByWorktreeId(
            repositoryTopology: store.repositoryTopologyAtom,
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab,
            declaredWorktreeIDs: visibleWorktreeIDs
        )
        var capabilityFactsByWorktreeID: [UUID: [LocationCapabilityFacts]] = [:]
        for (worktreeID, locations) in locationsByWorktreeID {
            capabilityFactsByWorktreeID[worktreeID] = locations.map { location in
                let structuralFacts = store.paneAtom.graphAtom.paneStructuralFacts(location.paneId)
                return LocationCapabilityFacts(
                    tabID: location.tabId,
                    paneID: location.paneId,
                    tab: store.tabLayoutAtom.tab(location.tabId),
                    zoomPresentation: store.panePresentationAtom.zoomPresentation(forTab: location.tabId),
                    paneStructuralFacts: structuralFacts,
                    isDrawerExpanded: structuralFacts?.ownedDrawerID == nil
                        ? nil
                        : store.paneAtom.isDrawerExpanded(for: location.paneId)
                )
            }.sorted { lhs, rhs in
                if lhs.tabID != rhs.tabID {
                    return lhs.tabID.uuidString < rhs.tabID.uuidString
                }
                return lhs.paneID.uuidString < rhs.paneID.uuidString
            }
        }
        return CapabilityFactsFingerprint(
            activeTabID: activeTabID,
            isManagementLayerActive: isManagementLayerActive,
            locationsByWorktreeID: capabilityFactsByWorktreeID
        )
    }

    private func commandPresentationRequests(
        visibleWorktreeIDs: Set<UUID>
    ) -> Set<RepoExplorerCommandPresentationRequest> {
        let nextSortOrder = repoExplorerPrefs.sortOrder.toggled
        var requests = RepoExplorerToolbarCommandPresentation.requests(
            nextSortOrder: nextSortOrder
        )

        for worktreeID in visibleWorktreeIDs {
            guard let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
                let repo = store.repositoryTopologyAtom.repo(worktree.repoId)
            else { continue }
            requests.formUnion(
                RepoExplorerWorktreeCommandPresentation.requests(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    isFavorite: repo.isFavorite,
                    showsFavoriteControl: worktree.isMainWorktree
                )
            )
        }
        return requests
    }

    private func worktreeCommandPresentationRequests(
        worktreeIDs: Set<UUID>
    ) -> Set<RepoExplorerCommandPresentationRequest> {
        var requests: Set<RepoExplorerCommandPresentationRequest> = []
        for worktreeID in worktreeIDs {
            guard let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
                let repo = store.repositoryTopologyAtom.repo(worktree.repoId)
            else { continue }
            requests.formUnion(
                RepoExplorerWorktreeCommandPresentation.requests(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    isFavorite: repo.isFavorite,
                    showsFavoriteControl: worktree.isMainWorktree
                )
            )
        }
        return requests
    }
}
