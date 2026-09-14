import Foundation

extension ForgeActor {
    package func assertObservationLifetimes(_ assertion: FilesystemTopologyAssertion) async {
        let lifetimes = assertion.repositoryLifetimes
        hasBoundObservationLifetimes = true
        observationLifetimesByWorktreeID = assertion.worktreeLifetimes
        let changed = Set(observationLifetimesByRepositoryID.keys).union(lifetimes.keys).filter {
            observationLifetimesByRepositoryID[$0] != lifetimes[$0]
        }
        observationLifetimesByRepositoryID = lifetimes
        for repositoryID in changed {
            cancelProviderRequest(repoId: repositoryID)
            if var state = refreshStateByRepoId[repositoryID] {
                state.generation &+= 1
                state.activeRequestId = nil
                state.activeRequestSignature = nil
                state.lastSuccessfulRefreshAt = nil
                state.lastAttemptAt = nil
                state.stablePresentation = .unknown
                state.acceptedProjection = .stable(.unknown)
                refreshStateByRepoId[repositoryID] = state
            }
            if lifetimes[repositoryID] != nil {
                await requestRefreshIfDemanded(repoId: repositoryID, trigger: .scopeChanged, correlationId: nil)
            }
        }
    }

}
