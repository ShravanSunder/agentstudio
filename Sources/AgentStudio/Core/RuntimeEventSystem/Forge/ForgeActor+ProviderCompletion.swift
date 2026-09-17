import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    func completeProviderRequest(
        _ request: ProviderRequest,
        outcome: ForgePullRequestQueryOutcome
    ) async {
        defer { flushPerformanceSnapshot() }
        providerTasksByRequestId.removeValue(forKey: request.id)
        providerRepoIdByRequestId.removeValue(forKey: request.id)
        recordPhysicalPerformanceState()
        guard !isShuttingDown else { return }
        performanceAccumulator.recordExecution(.completed)
        guard var state = await validatedStateForProviderCompletion(request) else { return }

        state.activeRequestId = nil
        state.activeRequestSignature = nil
        let completionTime = monotonicNow()
        let diagnosticEvent: ForgeEvent?
        if requestRemainsCurrentForResultPublication(request) {
            performanceAccumulator.recordValidation(.current)
            switch outcome {
            case .complete:
                break
            case .truncated, .rateLimited, .failed:
                performanceAccumulator.recordExecution(.failed)
            }
            diagnosticEvent = applyOutcome(
                outcome,
                to: &state,
                request: request,
                completionTime: completionTime
            )
            applyFailureHonestyThreshold(to: &state)
        } else {
            performanceAccumulator.recordValidation(.staleScope)
            diagnosticEvent = nil
        }

        let completionProjection = PullRequestRepositoryProjection.stable(
            state.stablePresentation
        )
        let projectionChanged = state.acceptedProjection != completionProjection
        if !projectionChanged {
            performanceAccumulator.recordPublication(.equal)
        }
        state.acceptedProjection = completionProjection
        let followUpTrigger = captureFollowUpDecision(
            state: &state,
            request: request,
            completionTime: completionTime
        )
        refreshStateByRepoId[request.repoId] = state

        if projectionChanged {
            await emitForgeEvent(
                repoId: request.repoId,
                correlationId: request.correlationId,
                event: .pullRequestRepositoryProjectionChanged(
                    repoId: request.repoId,
                    projection: completionProjection,
                    invalidatedBranches: []
                )
            )
        }
        if let diagnosticEvent {
            await emitForgeEvent(
                repoId: request.repoId,
                correlationId: request.correlationId,
                event: diagnosticEvent
            )
        }

        switch outcome {
        case .complete:
            settleExplicitUpdateAttempts(
                matching: request,
                outcome: .completed,
                requiresMatchingScope: true
            )
        case .failed:
            settleExplicitUpdateAttempts(
                matching: request,
                outcome: .failed,
                requiresMatchingScope: true
            )
        case .truncated, .rateLimited:
            break
        }

        guard !isShuttingDown,
            let currentState = refreshStateByRepoId[request.repoId],
            currentState.generation == request.generation,
            currentState.activeRequestId == nil
        else {
            await rearmAfterProviderPhysicalCompletion()
            return
        }
        if let followUpTrigger {
            await requestRefreshIfDemanded(
                repoId: request.repoId,
                trigger: followUpTrigger,
                correlationId: nil
            )
        }
        await rearmAfterProviderPhysicalCompletion()
    }

}

extension ForgeActor {
    private func applyOutcome(
        _ outcome: ForgePullRequestQueryOutcome,
        to state: inout RepositoryRefreshState,
        request: ProviderRequest,
        completionTime: Duration
    ) -> ForgeEvent? {
        performanceAccumulator.recordQueryOutcome(outcome)
        switch outcome {
        case .complete(let pullRequests):
            if state.hasEmittedUnavailable {
                performanceAccumulator.recordRecovery()
            }
            let priorConfirmedFacts = ForgePresentationFacts.confirmedFacts(in: state.stablePresentation) ?? [:]
            let representedBranches = representedBranches(repoId: request.repoId)
            var confirmedFactsByBranch = priorConfirmedFacts.filter { branch, _ in
                representedBranches.contains(branch)
            }
            let refreshedFactsByBranch = ForgePullRequestFactsProjector.project(
                pullRequests: pullRequests,
                demandedBranches: request.demandedBranches
            )
            for branch in request.demandedBranches {
                confirmedFactsByBranch[branch] = refreshedFactsByBranch[branch]
            }
            if priorConfirmedFacts == confirmedFactsByBranch {
                performanceAccumulator.recordPublication(.equal)
            }
            state.lastSuccessfulRefreshAt = completionTime
            state.backoffUntil = nil
            state.consecutiveFailureCount = 0
            state.consecutiveUnsuccessfulAttempts = 0
            state.hasEmittedUnavailable = false
            state.stablePresentation = .ready(
                confirmedFactsByBranch: confirmedFactsByBranch
            )
            return nil
        case .truncated:
            state.consecutiveUnsuccessfulAttempts += 1
            state.backoffUntil = minimumRetryAt(state: state, completionTime: completionTime)
            return .refreshFailed(
                repoId: request.repoId,
                error: "GitHub pull request result reached the 200-item cap"
            )
        case .rateLimited(let retryAfterSeconds):
            state.consecutiveUnsuccessfulAttempts += 1
            let retryAfterDeadline = retryAfterSeconds.map {
                completionTime + .seconds(Int64($0))
            }
            state.backoffUntil = max(
                minimumRetryAt(state: state, completionTime: completionTime),
                retryAfterDeadline ?? .zero
            )
            return .rateLimited(repoId: request.repoId, retryAfterSeconds: retryAfterSeconds)
        case .failed(let message):
            state.consecutiveFailureCount += 1
            state.consecutiveUnsuccessfulAttempts += 1
            let manualBackoffUntil =
                completionTime
                + AppPolicies.ForgeRefresh.failureBackoffDelay(
                    forConsecutiveFailureCount: state.consecutiveFailureCount
                )
            if request.trigger.usesAutomaticFailureFloor {
                let automaticRetryFloor =
                    (state.lastAttemptAt ?? completionTime)
                    + AppPolicies.ForgeRefresh.automaticFailureRetryFloor
                state.backoffUntil = max(manualBackoffUntil, automaticRetryFloor)
            } else {
                state.backoffUntil = manualBackoffUntil
            }
            return .refreshFailed(repoId: request.repoId, error: message)
        }
    }

    private func minimumRetryAt(
        state: RepositoryRefreshState,
        completionTime: Duration
    ) -> Duration {
        (state.lastAttemptAt ?? completionTime) + AppPolicies.Forge.automaticRefreshMinimumInterval
    }

}
