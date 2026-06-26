import Foundation

extension WorkspaceSQLiteStoreBackend {
    func loadRepositoryTopology(workspaceId: UUID) throws -> WorkspaceCoreRepository.RepositoryTopologyRecord {
        guard try coreRepository.fetchWorkspace(id: workspaceId) != nil else {
            throw BackendUninitializedError()
        }
        return try coreRepository.fetchRepositoryTopology(workspaceId: workspaceId)
    }

    func resolveWorkspaceRestoreContext(
        preferredWorkspaceId: UUID,
        localRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository,
        repairLocalRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceSQLiteDatastore.ResolvedWorkspaceRestoreContext {
        let workspaceId =
            try coreRepository.fetchActiveOrPreferredRecoverableStagedWorkspaceId(
                preferredWorkspaceId: preferredWorkspaceId
            )
            ?? resolvedWorkspaceId(preferredWorkspaceId: preferredWorkspaceId)
            ?? coreRepository.fetchRecoverableStagedWorkspaceId(preferredWorkspaceId: preferredWorkspaceId)
        guard let workspaceId,
            let workspace = try coreRepository.fetchWorkspace(id: workspaceId)
        else {
            throw BackendUninitializedError()
        }
        let coreCompletedAt = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspace.id)
        let stagedAt = try coreRepository.fetchStagedWorkspaceSQLiteSnapshotAt(workspaceId: workspace.id)
        let isRecoveringStagedSnapshot = coreCompletedAt == nil
        guard let snapshotToken = coreCompletedAt ?? stagedAt else {
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
        let localSnapshotIsUsable: Bool
        switch readLocalSnapshot(localRepository, matching: snapshotToken) {
        case .matched(let restoredCursorState, let restoredWindowState):
            cursorState = restoredCursorState
            windowState = restoredWindowState
            localSnapshotIsUsable = true
        case .needsDefaultLocalState, .unavailable:
            cursorState = WorkspaceSQLiteStateBridge.defaultCursorState(tabShells: tabShells, tabGraph: tabGraph)
            windowState = nil
            var didRepairLocalSnapshot = false
            if localRepairDisposition == .repairAllowed {
                didRepairLocalSnapshot = await repairLocalSnapshotIfPossible(
                    workspaceId: workspace.id,
                    cursorState: cursorState,
                    windowState: windowState,
                    completedAt: snapshotToken,
                    repairLocalRepositoryForWorkspaceId: repairLocalRepositoryForWorkspaceId
                )
            }
            localSnapshotIsUsable = didRepairLocalSnapshot
        }
        if isRecoveringStagedSnapshot {
            guard localSnapshotIsUsable else {
                throw BackendError.incompleteWorkspaceSnapshot(workspace.id)
            }
            try markWorkspaceSnapshotCommitted(workspaceId: workspace.id, committedAt: snapshotToken)
        }

        return .init(
            workspace: workspace,
            topology: topology,
            paneGraph: paneGraph,
            tabShells: tabShells,
            tabGraph: tabGraph,
            cursorState: cursorState,
            windowState: windowState,
            snapshotStatus: coreCompletedAt.map(WorkspaceSQLiteDatastore.RestoreSnapshotStatus.completed)
                ?? .recoveredStaged(snapshotToken),
            recoveryEvents: []
        )
    }

    func loadCompletedSnapshot(
        preferredWorkspaceId: UUID,
        localRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository,
        repairLocalRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceSQLiteSnapshot {
        let context = try await resolveWorkspaceRestoreContext(
            preferredWorkspaceId: preferredWorkspaceId,
            localRepositoryForWorkspaceId: localRepositoryForWorkspaceId,
            repairLocalRepositoryForWorkspaceId: repairLocalRepositoryForWorkspaceId
        )
        let state = try WorkspaceSQLiteStateBridge.persistableState(
            from: .init(
                workspace: context.workspace,
                topology: context.topology,
                paneGraph: context.paneGraph,
                tabShells: context.tabShells,
                tabGraph: context.tabGraph,
                cursorState: context.cursorState,
                windowState: context.windowState
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

    @discardableResult
    private func repairLocalSnapshotIfPossible(
        workspaceId: UUID,
        cursorState: WorkspaceLocalRepository.CursorStateRecord,
        windowState: WorkspaceLocalRepository.WindowStateRecord?,
        completedAt: Date,
        repairLocalRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async -> Bool {
        do {
            let localRepository = try await repairLocalRepositoryForWorkspaceId(workspaceId)
            try localRepository.replaceWorkspaceSnapshotLocalState(
                cursorState: cursorState,
                windowState: windowState,
                completedAt: completedAt
            )
            return true
        } catch {
            return false
        }
    }
}
