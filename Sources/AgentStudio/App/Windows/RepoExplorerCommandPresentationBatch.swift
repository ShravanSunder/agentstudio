import AgentStudioCore
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
    @ObservationIgnored private var observationID: UUID?

    init(
        store: WorkspaceStore,
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom,
        dispatcher: AppCommandDispatcher
    ) {
        self.store = store
        self.repoExplorerPrefs = repoExplorerPrefs
        self.visibleWorktrees = visibleWorktrees
        self.dispatcher = dispatcher
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
        let nextSnapshot = withObservationTracking {
            observeApprovedCapabilityFacts()
            return dispatcher.repoExplorerCommandPresentationSnapshot(
                requests: commandPresentationRequests(),
                generation: nextGeneration
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh(observationID: observationID)
            }
        }
        if snapshot != nextSnapshot {
            snapshot = nextSnapshot
        }
    }

    private func observeApprovedCapabilityFacts() {
        _ = store.tabLayoutAtom.tabs
        _ = store.tabLayoutAtom.activeTabId
        _ = store.panePresentationAtom.zoomPresentationsByTabId
        _ = atom(\.managementLayer).isActive
        _ = store.repositoryTopologyAtom.repos
        for paneID in store.paneAtom.graphAtom.paneIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let structuralFacts = store.paneAtom.graphAtom.paneStructuralFacts(paneID)
            if structuralFacts?.ownedDrawerID != nil {
                _ = store.paneAtom.isDrawerExpanded(for: paneID)
            }
        }
    }

    private func commandPresentationRequests() -> Set<RepoExplorerCommandPresentationRequest> {
        let nextVisibilityMode: RepoExplorerVisibilityMode =
            repoExplorerPrefs.repoVisibilityMode == .favoritesOnly ? .all : .favoritesOnly
        let nextSortOrder = repoExplorerPrefs.sortOrder.toggled
        var requests = RepoExplorerToolbarCommandPresentation.requests(
            nextVisibilityMode: nextVisibilityMode,
            nextSortOrder: nextSortOrder
        )

        let visibleWorktreeIDs = visibleWorktrees.visibleWorktreeIds
        for repo in store.repositoryTopologyAtom.repos {
            for worktree in repo.worktrees where visibleWorktreeIDs.contains(worktree.id) {
                requests.formUnion(
                    RepoExplorerWorktreeCommandPresentation.requests(
                        worktreeId: worktree.id,
                        repoId: repo.id,
                        isFavorite: repo.isFavorite,
                        showsFavoriteControl: worktree.isMainWorktree
                    )
                )
            }
        }
        return requests
    }
}
