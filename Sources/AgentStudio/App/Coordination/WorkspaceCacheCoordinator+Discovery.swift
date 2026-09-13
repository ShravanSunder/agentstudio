import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

@MainActor
extension WorkspaceCacheCoordinator {
    @discardableResult
    func handleRepoDiscovered(
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
            let initialDelta = existingRepo == nil ? initialDiscoveryDelta(repoId: repoId, eventId: eventId) : nil
            if shouldApplyTopologyEffects, let initialDelta {
                topologyEffectHandler?.topologyDidChange(initialDelta)
            }
            return initialDelta
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
            delta = existingRepo == nil ? initialDiscoveryDelta(repoId: repoId, eventId: eventId) : acceptedDelta
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

    private func initialDiscoveryDelta(repoId: UUID, eventId: UUID) -> WorktreeTopologyDelta {
        WorktreeTopologyDelta(
            repoId: repoId,
            addedWorktreeIds: workspaceStore.repositoryTopologyAtom.repo(repoId)?.worktrees.map(\.id) ?? [],
            removedWorktrees: [],
            preservedWorktreeIds: [],
            didChange: true,
            traceId: eventId
        )
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

    func handleReposDiscovered(
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

    private static func buildDiscoveredWorktreeList(
        clonePath: URL,
        linkedPaths: [URL],
        stableIdentity: DiscoveredRepoStableIdentity
    ) -> RepositoryScannedWorktrees {
        let normalizedClonePath = clonePath.standardizedFileURL
        let normalizedLinkedPaths = Array(Set(linkedPaths.map(\.standardizedFileURL)))
            .filter { $0 != normalizedClonePath }
            .sorted(by: sortPaths)

        let mainWorktree = RepositoryScannedMainWorktree(
            name: normalizedClonePath.lastPathComponent,
            path: normalizedClonePath,
            stableKey: stableIdentity.worktreeStableKeysByPath[normalizedClonePath]
        )
        let linkedWorktrees = normalizedLinkedPaths.map { linkedPath in
            RepositoryScannedLinkedWorktree(
                name: linkedPath.lastPathComponent,
                path: linkedPath,
                stableKey: stableIdentity.worktreeStableKeysByPath[linkedPath]
            )
        }
        return RepositoryScannedWorktrees(main: mainWorktree, linked: linkedWorktrees)
    }

    private static func sortPaths(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}
