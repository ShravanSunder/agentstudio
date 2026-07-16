import Foundation

extension WorkspaceSQLiteStoreBackend {
    func loadCompletedSnapshot(
        localRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceSQLiteSnapshot {
        let workspace = try strictlySelectedCompletedWorkspace()
        guard
            let snapshotToken = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(
                workspaceId: workspace.id
            )
        else {
            throw BackendError.incompleteWorkspaceSnapshot(workspace.id)
        }

        let paneGraph = try coreRepository.fetchPaneGraph(workspaceId: workspace.id)
        let tabShells = try coreRepository.fetchTabShells(workspaceId: workspace.id)
        let tabGraph = try coreRepository.fetchTabGraph(workspaceId: workspace.id)
        let localRepository = try await localRepositoryForWorkspaceId(workspace.id)
        let cursorState: WorkspaceLocalRepository.CursorStateRecord
        let windowState: WorkspaceLocalRepository.WindowStateRecord?
        switch readLocalSnapshot(localRepository, matching: snapshotToken) {
        case .matched(let restoredCursorState, let restoredWindowState):
            cursorState = restoredCursorState
            windowState = restoredWindowState
        case .notCompletedAtCoreToken:
            throw BackendError.localWorkspaceSnapshotNotCompleted(workspace.id)
        case .unavailable(let error):
            throw error
        }

        return try WorkspaceSQLiteStateBridge.workspaceSnapshot(
            from: .init(
                workspace: workspace,
                paneGraph: paneGraph,
                tabShells: tabShells,
                tabGraph: tabGraph,
                cursorState: cursorState,
                windowState: windowState
            )
        )
    }

    func hasCompletedSnapshot(workspaceId: UUID, localRepository: WorkspaceLocalRepository) throws -> Bool {
        guard let coreCompletedAt = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId)
        else {
            return false
        }
        return try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == coreCompletedAt
    }
}
