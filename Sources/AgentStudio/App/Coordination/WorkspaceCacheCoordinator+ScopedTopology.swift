import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

extension WorkspaceCacheCoordinator {
    func consumeWatchedFolderObservation(_ observation: WatchedFolderTopologyObservation, sequence: UInt64) async {
        await waitForRetentionCommit()
        let sourceID = observation.registration.sourceID
        guard sequence > (appliedScopeSequences[sourceID] ?? 0) else { return }
        guard await validateSourceObservations([observation]) else { return }
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
            switch await RepositoryLifecycleReconciliation.prepare(
                input, observation: observation, performanceTraceRecorder: performanceTraceRecorder)
            {
            case .outsideScope:
                return
            case .invalid:
                Self.logger.error("Scoped topology rejected invalid canonical identity")
                return
            case .prepared(let change):
                await waitForRetentionCommit()
                guard await validateSourceObservations([observation]),
                    sequence > (appliedScopeSequences[sourceID] ?? 0)
                else { return }
                // Source validation suspends; collection can acquire its reservation during that await.
                await waitForRetentionCommit()
                guard sequence > (appliedScopeSequences[sourceID] ?? 0) else { return }
                let publicationStart = ContinuousClock.now
                let previousLifetimes = workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes
                guard coordinator.applyRepositoryLifecycleChange(change) else { continue }
                topologyPersistence?.recordReparenting(
                    change.reparenting, revision: workspaceStore.repositoryTopologyAtom.lifecycleRevision
                )
                let firstApplication = appliedScopeSequences[sourceID] == nil
                appliedScopeSequences[sourceID] = sequence
                var unavailableRepositoryIDs: [UUID] = []
                for delta in change.deltas {
                    if previousLifetimes[delta.repoId]
                        != workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes[delta.repoId]
                    {
                        repoCache.removePullRequestFacts(forRepository: delta.repoId)
                    }
                    for removed in delta.removedWorktrees {
                        for _ in coordinator.clearPaneAssociations(forRemovedWorktreeID: removed.id) {
                            performanceTraceRecorder?.recordPaneAssociationOutcome(.topologyRemoved)
                        }
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
                performanceTraceRecorder?.recordDuration(
                    .repositoryLifecyclePublication,
                    duration: publicationStart.duration(to: .now),
                    attributes: [
                        "agentstudio.performance.repository_lifecycle.changed_family.count": .int(change.deltas.count)
                    ])
                for repositoryID in unavailableRepositoryIDs {
                    await syncScope(
                        .unregisterForgeRepo(repoId: repositoryID, expectedLifetime: previousLifetimes[repositoryID]))
                }
                let topology = workspaceStore.repositoryTopologyAtom
                if topology.worktreePathIndexGeneration != observation.baselineMembershipRevision {
                    await syncScope(
                        .updateRepositoryScanBaseline(
                            repositories: topology.repos,
                            membershipRevision: topology.worktreePathIndexGeneration))
                }
                refreshTraceIdentity()
                if workspaceStore.repositoryTopologyAtom.lifecycleRevision != input.revision {
                    do { try await topologyPersistence?.flushAsync() } catch {
                        Self.logger.warning("Repository topology persistence will retry after failed acknowledgement")
                    }
                }
                await rescheduleRepositoryRetention()
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
