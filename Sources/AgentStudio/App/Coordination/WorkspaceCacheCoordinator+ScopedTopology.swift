import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

extension WorkspaceCacheCoordinator {
    func consumeWatchedFolderObservation(_ observation: WatchedFolderTopologyObservation, sequence: UInt64) async {
        let sourceID = observation.registration.sourceID
        guard sequence > (appliedScopeSequences[sourceID] ?? 0) else { return }
        guard await validateSourceObservation(observation) else { return }
        for _ in 0..<AppPolicies.RepositoryRetention.reconciliationRetryLimit {
            let coordinator = workspaceStore.mutationCoordinator
            let input = coordinator.captureRepositoryLifecycleInput()
            guard
                workspaceStore.repositoryTopologyAtom.watchedPaths.contains(where: {
                    $0.path.standardizedFileURL == observation.root.standardizedFileURL && $0.id == sourceID.rootID
                })
            else { return }
            guard
                observation.baselineMembershipRevision
                    == workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration
            else {
                await refreshStaleObservation()
                return
            }
            switch await RepositoryLifecycleReconciliation.prepare(input, observation: observation) {
            case .outsideScope:
                return
            case .invalid:
                Self.logger.error("Scoped topology rejected invalid canonical identity")
                return
            case .prepared(let change):
                guard await validateSourceObservation(observation),
                    sequence > (appliedScopeSequences[sourceID] ?? 0)
                else { return }
                guard coordinator.applyRepositoryLifecycleChange(change) else { continue }
                topologyPersistence?.recordReparenting(
                    change.reparenting, revision: workspaceStore.repositoryTopologyAtom.lifecycleRevision
                )
                let firstApplication = appliedScopeSequences[sourceID] == nil
                appliedScopeSequences[sourceID] = sequence
                var unavailableRepositoryIDs: [UUID] = []
                for delta in change.deltas {
                    for removed in delta.removedWorktrees {
                        _ = coordinator.clearPaneAssociations(forRemovedWorktreeID: removed.id)
                        repoCache.removeWorktree(removed.id)
                    }
                    if workspaceStore.repositoryTopologyAtom.isRepoUnavailable(delta.repoId) {
                        repoCache.removeRepo(delta.repoId)
                        unavailableRepositoryIDs.append(delta.repoId)
                    } else if repoCache.repoEnrichment(for: delta.repoId) == nil {
                        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: delta.repoId))
                    }
                }
                if firstApplication || !change.deltas.isEmpty {
                    topologyEffectHandler?.topologyDidChange(change.deltas)
                }
                for repositoryID in unavailableRepositoryIDs {
                    await syncScope(.unregisterForgeRepo(repoId: repositoryID))
                }
                await syncScope(
                    .updateTopologyMembershipRevision(workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration)
                )
                refreshTraceIdentity()
                return
            }
        }
        await refreshStaleObservation()
    }

    private func refreshStaleObservation() async {
        let topology = workspaceStore.repositoryTopologyAtom
        await syncScope(
            .updateWatchedFolders(
                watchedPaths: topology.watchedPaths,
                restoringRepositories: topology.repos,
                membershipRevision: topology.worktreePathIndexGeneration
            ))
    }
}
