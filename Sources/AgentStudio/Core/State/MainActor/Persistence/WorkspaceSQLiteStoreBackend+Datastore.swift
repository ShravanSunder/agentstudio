import Foundation

extension WorkspaceSQLiteStoreBackend {
    func loadCompletedSnapshot(
        preferredWorkspaceId: UUID,
        localRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository,
        repairLocalRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceSQLiteSnapshot {
        let workspaceId = try resolvedWorkspaceId(preferredWorkspaceId: preferredWorkspaceId)
        guard let workspaceId,
            let workspace = try coreRepository.fetchWorkspace(id: workspaceId)
        else {
            throw BackendUninitializedError()
        }
        let coreCompletedAt = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspace.id)
        guard let coreCompletedAt else {
            throw BackendError.incompleteWorkspaceSnapshot(workspace.id)
        }

        let topology = try coreRepository.fetchRepositoryTopology(workspaceId: workspace.id)
        let paneGraph = try coreRepository.fetchPaneGraph(workspaceId: workspace.id)
        let tabShells = try coreRepository.fetchTabShells(workspaceId: workspace.id)
        let tabGraph = try coreRepository.fetchTabGraph(workspaceId: workspace.id)
        let localRepository: WorkspaceLocalRepository?
        let localRepairDisposition: LocalSnapshotRepairDisposition
        do {
            localRepository = try await localRepositoryForWorkspaceId(workspace.id)
            localRepairDisposition = .repairAllowed
        } catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption {
            localRepository = nil
            localRepairDisposition = .repairAllowed
        } catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed {
            localRepository = nil
            localRepairDisposition = .repairBlockedByQuarantineFailure
        } catch {
            localRepository = nil
            localRepairDisposition = .repairAllowed
        }
        let cursorState: WorkspaceLocalRepository.CursorStateRecord
        let windowState: WorkspaceLocalRepository.WindowStateRecord?
        switch readLocalSnapshot(localRepository, matching: coreCompletedAt) {
        case .matched(let restoredCursorState, let restoredWindowState):
            cursorState = restoredCursorState
            windowState = restoredWindowState
        case .needsDefaultLocalState, .unavailable:
            cursorState = WorkspaceSQLiteStateBridge.defaultCursorState(tabShells: tabShells, tabGraph: tabGraph)
            windowState = nil
            if localRepairDisposition == .repairAllowed {
                await repairLocalSnapshotIfPossible(
                    workspaceId: workspace.id,
                    cursorState: cursorState,
                    windowState: windowState,
                    completedAt: coreCompletedAt,
                    repairLocalRepositoryForWorkspaceId: repairLocalRepositoryForWorkspaceId
                )
            }
        }

        let state = try WorkspaceSQLiteStateBridge.persistableState(
            from: .init(
                workspace: workspace,
                topology: topology,
                paneGraph: paneGraph,
                tabShells: tabShells,
                tabGraph: tabGraph,
                cursorState: cursorState,
                windowState: windowState
            )
        )
        return WorkspacePersistenceTransformer.sqliteSnapshot(from: state)
    }

    func hasCompletedSnapshot(workspaceId: UUID, localRepository: WorkspaceLocalRepository) throws -> Bool {
        guard let coreCompletedAt = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId)
        else {
            return false
        }
        return try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == coreCompletedAt
    }

    private func repairLocalSnapshotIfPossible(
        workspaceId: UUID,
        cursorState: WorkspaceLocalRepository.CursorStateRecord,
        windowState: WorkspaceLocalRepository.WindowStateRecord?,
        completedAt: Date,
        repairLocalRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async {
        do {
            let localRepository = try await repairLocalRepositoryForWorkspaceId(workspaceId)
            try localRepository.replaceWorkspaceSnapshotLocalState(
                cursorState: cursorState,
                windowState: windowState,
                completedAt: completedAt
            )
        } catch {
            return
        }
    }
}
