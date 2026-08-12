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
    private(set) var snapshot = RepoExplorerCommandPresentationSnapshot.empty

    private let store: WorkspaceStore
    private let repoExplorerPrefs: RepoExplorerSidebarPrefsAtom
    private let visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom
    private let dispatcher: AppCommandDispatcher
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var observationID: UUID?

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
        refresh(observationID: observationID)
    }

    func stop() {
        observationID = nil
    }

    private func refresh(observationID: UUID) {
        guard self.observationID == observationID else { return }
        let nextGeneration = snapshot.generation &+ 1
        let requests = withObservationTracking {
            let visibleWorktreeIDs = visibleWorktrees.visibleWorktreeIds
            observeApprovedCapabilityFacts(visibleWorktreeIDs: visibleWorktreeIDs)
            return commandPresentationRequests(visibleWorktreeIDs: visibleWorktreeIDs)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh(observationID: observationID)
            }
        }
        let nextSnapshot = dispatcher.repoExplorerCommandPresentationSnapshot(
            requests: requests,
            generation: nextGeneration
        )
        if snapshot != nextSnapshot {
            let affectedItemCount = Self.affectedItemCount(
                previous: snapshot.results,
                next: nextSnapshot.results
            )
            snapshot = nextSnapshot
            performanceTraceRecorder?.record(
                .repoExplorerCommandPresentation,
                attributes: [
                    "agentstudio.performance.repo_explorer.affected_item.count": .int(affectedItemCount),
                    "agentstudio.performance.repo_explorer.command_resolution.count": .int(requests.count),
                    "agentstudio.performance.repo_explorer.capability_snapshot.count": .int(1),
                ]
            )
        }
    }

    private static func affectedItemCount(
        previous: [RepoExplorerCommandPresentationRequest: Bool],
        next: [RepoExplorerCommandPresentationRequest: Bool]
    ) -> Int {
        Set(previous.keys).union(next.keys).count { request in
            previous[request] != next[request]
        }
    }

    private func observeApprovedCapabilityFacts(visibleWorktreeIDs: Set<UUID>) {
        _ = store.tabLayoutAtom.activeTabId
        _ = atom(\.managementLayer).isActive
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
        for locations in locationsByWorktreeID.values {
            for location in locations {
                _ = store.tabLayoutAtom.tab(location.tabId)
                _ = store.panePresentationAtom.zoomPresentation(forTab: location.tabId)
                let structuralFacts = store.paneAtom.graphAtom.paneStructuralFacts(location.paneId)
                if structuralFacts?.ownedDrawerID != nil {
                    _ = store.paneAtom.isDrawerExpanded(for: location.paneId)
                }
            }
        }
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
}
