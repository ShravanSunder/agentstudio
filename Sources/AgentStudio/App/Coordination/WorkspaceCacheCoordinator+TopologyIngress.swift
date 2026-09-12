import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

extension WorkspaceCacheCoordinator {
    func handleTopology(_ envelope: SystemEnvelope) {
        guard case .topology(let topologyEvent) = envelope.event else { return }

        switch topologyEvent {
        case .watchedFolderReconciled:
            preconditionFailure("scoped reconciliation requires async admission")
        case .repoDiscovered(let repoPath, _, let linkedWorktrees, let stableIdentity):
            handleRepoDiscovered(
                repoPath: repoPath,
                linkedWorktrees: linkedWorktrees,
                stableIdentity: stableIdentity,
                eventId: envelope.eventId
            )
        case .reposDiscovered(_, let repositories):
            handleReposDiscovered(
                repositories: repositories,
                eventId: envelope.eventId
            )
        case .repoRemoved(let repoPath):
            handleRepoRemoved(repoPath: repoPath)
        case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
            handleWorktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        case .worktreeUnregistered(let worktreeId, let repoId):
            handleWorktreeUnregistered(worktreeId: worktreeId, repoId: repoId)
        }
    }

    @discardableResult
    private func handleRepoDiscovered(
        repoPath: URL,
        linkedWorktrees: LinkedWorktreeInfo,
        stableIdentity: DiscoveredRepoStableIdentity?,
        eventId: UUID,
        shouldRefreshTraceIdentity: Bool = true,
        shouldApplyTopologyEffects: Bool = true
    ) -> WorktreeTopologyDelta? {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let normalizedRepoPath = repoPath.standardizedFileURL
        let preparedStableIdentity =
            stableIdentity
            ?? .prepare(repoPath: normalizedRepoPath, linkedWorktrees: linkedWorktrees)
        let incomingStableKey = preparedStableIdentity.repositoryStableKey
        let existingRepo =
            repositoryTopology.repo(stableKey: incomingStableKey)
            ?? repositoryTopology.repos.first { $0.repoPath.standardizedFileURL == normalizedRepoPath }
        let repoId: UUID
        let shouldInitializeRepoEnrichment: Bool
        if let repo = existingRepo {
            repoId = repo.id
            shouldInitializeRepoEnrichment = repoCache.repoEnrichment(for: repo.id) == nil
        } else {
            let repo = workspaceStore.mutationCoordinator.addRepo(
                at: normalizedRepoPath,
                stableKey: incomingStableKey
            )
            repoId = repo.id
            shouldInitializeRepoEnrichment = true
        }

        guard case .scanned(let linkedPaths) = linkedWorktrees else {
            if shouldInitializeRepoEnrichment {
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
            }
            if shouldRefreshTraceIdentity {
                refreshTraceIdentity()
            }
            return nil
        }
        guard let repo = repositoryTopology.repos.first(where: { $0.id == repoId }) else {
            Self.logger.error(
                "Repo id=\(repoId.uuidString, privacy: .public) not found after creation — store state inconsistency"
            )
            return nil
        }

        let delta: WorktreeTopologyDelta
        switch applyScannedWorktreeDiscovery(
            repo: repo,
            normalizedRepoPath: normalizedRepoPath,
            linkedPaths: linkedPaths,
            stableIdentity: preparedStableIdentity,
            eventId: eventId
        ) {
        case .accepted(let acceptedDelta):
            if existingRepo == nil, !acceptedDelta.didChange {
                delta = WorktreeTopologyDelta(
                    repoId: repoId,
                    addedWorktreeIds: repo.worktrees.map(\.id),
                    removedWorktrees: [],
                    preservedWorktreeIds: [],
                    didChange: true,
                    traceId: eventId
                )
            } else {
                delta = acceptedDelta
            }
        case .rejected(let rejection):
            Self.logger.error(
                "Rejecting scanned repo discovery for repoId=\(repo.id.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
            )
            return nil
        }
        guard delta.didChange else {
            if shouldInitializeRepoEnrichment {
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
            }
            if shouldRefreshTraceIdentity {
                refreshTraceIdentity()
            }
            return nil
        }

        for entry in delta.removedWorktrees {
            repoCache.removeWorktree(entry.id)
        }
        if !delta.removedWorktrees.isEmpty, topologyEffectHandler == nil {
            Self.logger.warning(
                "Topology delta has \(delta.removedWorktrees.count, privacy: .public) removed worktree(s) but no effect handler — pane association cleanup skipped"
            )
        }
        if shouldApplyTopologyEffects {
            topologyEffectHandler?.topologyDidChange(delta)
        }
        if shouldInitializeRepoEnrichment {
            repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        }
        if shouldRefreshTraceIdentity {
            refreshTraceIdentity()
        }
        return delta
    }

    private enum ScannedWorktreeDiscoveryRejection {
        case reconciliation(RepositoryWorktreeReconciliationRejection)
        case reassociation(RepositoryReassociationRejection)
    }

    private enum ScannedWorktreeDiscoveryResult {
        case accepted(WorktreeTopologyDelta)
        case rejected(ScannedWorktreeDiscoveryRejection)
    }

    private func applyScannedWorktreeDiscovery(
        repo: Repo,
        normalizedRepoPath: URL,
        linkedPaths: [URL],
        stableIdentity: DiscoveredRepoStableIdentity,
        eventId: UUID
    ) -> ScannedWorktreeDiscoveryResult {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let scannedWorktrees = Self.buildDiscoveredWorktreeList(
            clonePath: normalizedRepoPath,
            linkedPaths: linkedPaths,
            stableIdentity: stableIdentity
        )
        if repositoryTopology.isRepoUnavailable(repo.id) {
            let reassociation = workspaceStore.mutationCoordinator.reassociateRepo(
                repo.id,
                to: normalizedRepoPath,
                scannedWorktrees: scannedWorktrees,
                traceId: eventId
            )
            switch reassociation {
            case .accepted(let acceptance):
                return .accepted(acceptance.delta)
            case .rejected(let rejection):
                return .rejected(.reassociation(rejection))
            }
        }

        let reconciliation = workspaceStore.mutationCoordinator.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: scannedWorktrees,
            traceId: eventId
        )
        switch reconciliation {
        case .accepted(let acceptance):
            return .accepted(acceptance.delta)
        case .rejected(let rejection):
            return .rejected(.reconciliation(rejection))
        }
    }

    private func handleReposDiscovered(
        repositories: [DiscoveredRepoTopologyInfo],
        eventId: UUID
    ) {
        guard !repositories.isEmpty else { return }
        var topologyDeltas: [WorktreeTopologyDelta] = []
        workspaceStore.mutationCoordinator.performBatchedTopologyMutation {
            for repository in repositories {
                if let delta = handleRepoDiscovered(
                    repoPath: repository.repoPath,
                    linkedWorktrees: repository.linkedWorktrees,
                    stableIdentity: repository.stableIdentity,
                    eventId: eventId,
                    shouldRefreshTraceIdentity: false,
                    shouldApplyTopologyEffects: false
                ) {
                    topologyDeltas.append(delta)
                }
            }
        }
        if !topologyDeltas.isEmpty {
            topologyEffectHandler?.topologyDidChange(topologyDeltas)
        }
        refreshTraceIdentity()
    }

    private func handleRepoRemoved(repoPath: URL) {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        let normalizedRepoPath = repoPath.standardizedFileURL
        let removedStableKey = StableKey.fromPath(normalizedRepoPath)
        guard
            let repo = repositoryTopology.repos.first(where: {
                $0.repoPath.standardizedFileURL == normalizedRepoPath || $0.stableKey == removedStableKey
            })
        else { return }

        workspaceStore.mutationCoordinator.markRepoUnavailable(repo.id)
        let clearedPaneIds = Set(
            repo.worktrees.flatMap { worktree in
                workspaceStore.mutationCoordinator.clearPaneAssociations(
                    forRemovedWorktreeID: worktree.id
                )
            }
        )
        for _ in clearedPaneIds {
            performanceTraceRecorder?.recordPaneAssociationOutcome(.topologyRemoved)
        }
        if !clearedPaneIds.isEmpty {
            Self.logger.info(
                "Repo removed at path=\(repoPath.path, privacy: .public); cleared \(clearedPaneIds.count, privacy: .public) pane association(s)"
            )
        }
        repoCache.removeRepo(repo.id)
        topologyEffectHandler?.topologyDidChange(
            WorktreeTopologyDelta(
                repoId: repo.id,
                addedWorktreeIds: [],
                removedWorktrees: repo.worktrees.map { RemovedWorktreeEntry(id: $0.id, path: $0.path) },
                preservedWorktreeIds: [],
                didChange: true,
                traceId: nil
            )
        )
        refreshTraceIdentity()
        Task { [weak self] in
            await self?.syncScope(.unregisterForgeRepo(repoId: repo.id))
        }
    }

    private func handleWorktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL) {
        let repositoryTopology = workspaceStore.repositoryTopologyAtom
        guard let repo = repositoryTopology.repos.first(where: { $0.id == repoId }) else {
            Self.logger.debug(
                "Ignoring worktree registration for unknown repoId=\(repoId.uuidString, privacy: .public)"
            )
            return
        }

        var worktrees = repo.worktrees
        if !worktrees.contains(where: { $0.id == worktreeId }) {
            worktrees.append(
                Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: rootPath.lastPathComponent,
                    path: rootPath,
                    isMainWorktree: false
                )
            )
            let reconciliation = workspaceStore.mutationCoordinator.reconcileDiscoveredWorktrees(
                repo.id,
                worktrees: worktrees
            )
            switch reconciliation {
            case .accepted(let acceptance):
                topologyEffectHandler?.topologyDidChange(acceptance.delta)
                refreshTraceIdentity()
            case .rejected(let rejection):
                Self.logger.error(
                    "Rejecting worktree registration for repoId=\(repo.id.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
                )
            }
        }
    }

    private func handleWorktreeUnregistered(worktreeId: UUID, repoId: UUID) {
        let unregistration = workspaceStore.mutationCoordinator.unregisterWorktree(
            worktreeId,
            from: repoId
        )
        switch unregistration {
        case .accepted(let acceptance):
            for entry in acceptance.delta.removedWorktrees {
                repoCache.removeWorktree(entry.id)
            }
            topologyEffectHandler?.topologyDidChange(acceptance.delta)
            refreshTraceIdentity()
        case .rejected(let rejection):
            Self.logger.error(
                "Rejecting worktree unregistration for repoId=\(repoId.uuidString, privacy: .public): \(String(describing: rejection), privacy: .public)"
            )
        }
    }

}
