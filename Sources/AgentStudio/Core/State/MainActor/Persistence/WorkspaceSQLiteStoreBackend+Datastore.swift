import Foundation

extension WorkspaceSQLiteStoreBackend {
    func loadCompletedSnapshot(
        localRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceCoreLoadSnapshot {
        let authoritativeSnapshot = try strictlySelectedAuthoritativeSnapshot()
        let localRepository = try? await localRepositoryForWorkspaceId(authoritativeSnapshot.workspace.id)
        let localCursorState = localRepository.flatMap { repository in
            try? repository.fetchCursorState()
        }
        let localWindowState = localRepository.flatMap { repository in
            try? repository.fetchWindowState()
        }
        let workspaceSnapshot = try WorkspaceSQLiteStateBridge.workspaceSnapshot(
            from: .init(
                workspace: authoritativeSnapshot.workspace,
                paneGraph: authoritativeSnapshot.paneGraph,
                tabShells: authoritativeSnapshot.tabShells,
                tabGraph: authoritativeSnapshot.tabGraph,
                cursorState: WorkspaceSQLiteStateBridge.localCursorStateForComposition(
                    persisted: localCursorState,
                    paneGraph: authoritativeSnapshot.paneGraph,
                    tabGraph: authoritativeSnapshot.tabGraph
                ),
                windowState: localWindowState
            )
        )
        return WorkspaceCoreLoadSnapshot(
            workspace: workspaceSnapshot,
            repositoryTopology: WorkspaceSQLiteStateBridge.repositoryTopologySnapshot(
                topology: authoritativeSnapshot.topology,
                updatedAt: authoritativeSnapshot.workspace.updatedAt
            )
        )
    }
}
