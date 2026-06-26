import Foundation

extension WorkspaceSQLiteDatastore {
    func resolveWorkspaceRestoreContext(preferredWorkspaceId: UUID) async -> ResolvedWorkspaceRestoreContextResult {
        do {
            let backend = try resolvedBackend()
            let recoverableStagedWorkspaceId =
                try backend.coreRepository.fetchActiveOrPreferredRecoverableStagedWorkspaceId(
                    preferredWorkspaceId: preferredWorkspaceId
                )
                ?? backend.coreRepository.fetchRecoverableStagedWorkspaceId(preferredWorkspaceId: preferredWorkspaceId)
            var context = try await backend.resolveWorkspaceRestoreContext(
                preferredWorkspaceId: preferredWorkspaceId,
                localRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedRestoreLocalRepository(
                        workspaceId: workspaceId,
                        operation: .workspaceLoad,
                        lane: .workspace
                    )
                },
                repairLocalRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedSaveLocalRepository(
                        workspaceId: workspaceId,
                        operation: .workspaceLoad,
                        lane: .workspace
                    )
                }
            )
            if recoverableStagedWorkspaceId == context.workspaceId {
                appendRecoveryEvent(
                    .init(
                        store: .workspace,
                        workspaceId: context.workspaceId,
                        recovery: .localStateRebuilt
                    ),
                    workspaceId: context.workspaceId
                )
            }
            context.recoveryEvents = drainRecoveryEvents(workspaceId: context.workspaceId)
            return .resolved(context)
        } catch is BackendUninitializedError {
            return .uninitialized(recoveryEvents: drainAllRecoveryEvents())
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainAllRecoveryEvents())
        }
    }

    func loadRepositoryTopology(workspaceId: UUID) async -> RepositoryTopologyLoadResult {
        do {
            return .loaded(try resolvedBackend().loadRepositoryTopology(workspaceId: workspaceId))
        } catch is BackendUninitializedError {
            return .uninitialized(recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func workspaceSQLiteSnapshot(
        from context: ResolvedWorkspaceRestoreContext
    ) throws -> WorkspaceSQLiteSnapshot {
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
}
