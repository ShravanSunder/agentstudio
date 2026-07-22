import Foundation

extension WorkspaceSQLiteStoreBackend {
    func loadCompletedSnapshot(
        localRepositoryForWorkspaceId: @Sendable (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceCoreLoadSnapshot {
        let authoritativeSnapshot = try strictlySelectedAuthoritativeSnapshot()
        let localState:
            (
                cursor: WorkspaceLocalRepository.CursorStateRecord,
                window: WorkspaceLocalRepository.WindowStateRecord?
            )? = try? await {
                let localRepository = try await localRepositoryForWorkspaceId(authoritativeSnapshot.workspace.id)
                return (
                    cursor: try localRepository.fetchCursorState(),
                    window: try localRepository.fetchWindowState()
                )
            }()
        let workspaceSnapshot = try WorkspaceSQLiteStateBridge.workspaceSnapshot(
            from: .init(
                workspace: authoritativeSnapshot.workspace,
                paneGraph: authoritativeSnapshot.paneGraph,
                tabShells: authoritativeSnapshot.tabShells,
                tabGraph: authoritativeSnapshot.tabGraph,
                cursorState: WorkspaceSQLiteStateBridge.localCursorStateForComposition(
                    persisted: localState?.cursor,
                    paneGraph: authoritativeSnapshot.paneGraph,
                    tabGraph: authoritativeSnapshot.tabGraph
                ),
                windowState: localState?.window
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
