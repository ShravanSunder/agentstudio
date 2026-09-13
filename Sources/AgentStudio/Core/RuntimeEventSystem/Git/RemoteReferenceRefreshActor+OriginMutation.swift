import Foundation

extension RemoteReferenceRefreshActor {
    @discardableResult
    package func setOrigin(
        repoId: UUID,
        expectedOrigin: String?,
        expectedLifetime: RepositoryObservationLifetime? = nil
    ) async -> Bool {
        guard !isShuttingDown, var registration = registrationsByRepoId[repoId],
            registration.observationLifetime == expectedLifetime
        else { return false }
        guard registration.expectedOrigin != expectedOrigin else { return true }
        let acceptsLocalOriginDiscovery =
            registration.expectedOrigin == nil
            && expectedOrigin != nil
            && (lastAcceptedOriginByRepoId[repoId] == nil || lastAcceptedOriginByRepoId[repoId] == expectedOrigin)
        let nextGeneration = nextTopologyGeneration(repoId: repoId)
        guard
            await beginOriginMutationInvalidation(
                registration: registration,
                mutationGeneration: nextGeneration
            )
        else {
            endIdentityInvalidationIfCurrent(repoId: repoId, topologyGeneration: nextGeneration)
            return false
        }
        settleExplicitUpdateAttempts(repoId: repoId, outcome: .obsolete)
        registration.expectedOrigin = expectedOrigin
        registration.topologyGeneration = nextGeneration
        registrationsByRepoId[repoId] = registration
        lastSuccessfulFetchAtByRepoId.removeValue(forKey: repoId)
        failureDeadlineByRepoId.removeValue(forKey: repoId)
        currentnessRetryAtByRepoId.removeValue(forKey: repoId)
        invalidatingRepositoryIds.remove(repoId)
        if acceptsLocalOriginDiscovery {
            await establishLocalAcceptance(repoId: repoId)
            guard acceptsCurrentIdentity(registration) else { return false }
        }
        if expectedOrigin != nil, demandedRepositoryIds.contains(repoId) {
            pendingRepositoryIds.insert(repoId)
        }
        admitPendingAttempts()
        rescheduleDeadline()
        return true
    }

    private func beginOriginMutationInvalidation(
        registration: RemoteReferenceRegistration,
        mutationGeneration: UInt64
    ) async -> Bool {
        invalidatingRepositoryIds.insert(registration.repoId)
        await invalidateAuthority(repoId: registration.repoId, topologyGeneration: mutationGeneration)
        guard
            acceptsOriginMutation(
                registration: registration,
                mutationGeneration: mutationGeneration
            )
        else { return false }

        await revokeActiveOperation(
            repoId: registration.repoId,
            alreadyInvalidating: true,
            expectedTopologyGeneration: registration.topologyGeneration
        )
        return acceptsOriginMutation(
            registration: registration,
            mutationGeneration: mutationGeneration
        )
    }

    private func acceptsOriginMutation(
        registration: RemoteReferenceRegistration,
        mutationGeneration: UInt64
    ) -> Bool {
        guard !isShuttingDown,
            latestTopologyGenerationByRepoId[registration.repoId] == mutationGeneration,
            let currentRegistration = registrationsByRepoId[registration.repoId]
        else { return false }
        return currentRegistration.observationLifetime == registration.observationLifetime
            && currentRegistration.topologyGeneration == registration.topologyGeneration
            && currentRegistration.expectedOrigin == registration.expectedOrigin
            && currentRegistration.repositoryPath == registration.repositoryPath
            && currentRegistration.remoteName == registration.remoteName
            && currentRegistration.worktreeIds == registration.worktreeIds
    }

    private func endIdentityInvalidationIfCurrent(repoId: UUID, topologyGeneration: UInt64) {
        guard latestTopologyGenerationByRepoId[repoId] == topologyGeneration else { return }
        invalidatingRepositoryIds.remove(repoId)
    }
}
