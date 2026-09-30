import AgentStudioInfrastructure
import Foundation

extension GitWorkingDirectoryProjector {
    struct MaterializedGitStatus: Sendable {
        let result: GitWorkingTreeStatusResult
        let facts: GitWorkingTreeStatusFacts
        let detail: GitWorkingTreeLineDetail?
        let refreshedDetail: Bool
        let capacityCompletionGeneration: UInt64?
    }

    func materializeCompleteStatus(
        facts: GitWorkingTreeStatusFacts,
        changeset: FileChangeset
    ) async -> MaterializedGitStatus {
        let worktreeId = changeset.worktreeId
        let acceptedFacts = lastAcceptedStatusFactsByWorktreeId[worktreeId]
        let acceptedDetail = lastAcceptedLineDetailByWorktreeId[worktreeId]
        let detailIsFresh =
            lastAcceptedLineDetailAtByWorktreeId[worktreeId].map {
                deadlineClock.now - $0 < refreshPolicy.lineDetailFreshnessInterval
            } ?? false
        // Synthetic registration/attention refreshes intentionally carry an
        // empty path set even when their changeset is marked Git-internal.
        // They refresh facts, but do not prove that worktree content changed.
        let contentWasInvalidated = !changeset.paths.isEmpty
        let isExplicit = refreshAttribution.admittedDemandClassByWorktreeId[worktreeId] == "explicit"
        if facts.exactCleanAuthority != nil {
            recordAvoidedPhysicalDetailReadTelemetry()
            let exactEmptyDetail = GitWorkingTreeLineDetail(linesAdded: 0, linesDeleted: 0)
            return MaterializedGitStatus(
                result: .available(facts.composing(exactEmptyDetail)),
                facts: facts,
                detail: exactEmptyDetail,
                refreshedDetail: true,
                capacityCompletionGeneration: nil
            )
        }
        let needsDetail =
            acceptedDetail == nil
            || acceptedFacts != facts
            || contentWasInvalidated
            || isExplicit
            || !detailIsFresh

        if !needsDetail, let acceptedDetail {
            return MaterializedGitStatus(
                result: .available(facts.composing(acceptedDetail)),
                facts: facts,
                detail: acceptedDetail,
                refreshedDetail: false,
                capacityCompletionGeneration: nil
            )
        }

        let capacityCompletionGeneration = gitWorkingTreeProvider.physicalCompletionGeneration()
        switch await gitWorkingTreeProvider.lineDetailResult(for: changeset.rootPath) {
        case .available(let detail):
            return MaterializedGitStatus(
                result: .available(facts.composing(detail)),
                facts: facts,
                detail: detail,
                refreshedDetail: true,
                capacityCompletionGeneration: capacityCompletionGeneration
            )
        case .unavailable(let unavailable):
            return MaterializedGitStatus(
                result: .unavailable(unavailable),
                facts: facts,
                detail: nil,
                refreshedDetail: false,
                capacityCompletionGeneration: capacityCompletionGeneration
            )
        }
    }
    func computeAndEmit(changeset: FileChangeset) async {
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        if let factSink, let scope = openRefreshFactScopeByWorktreeId[changeset.worktreeId] {
            factSink(scope, .refreshStarted)
        }

        // Provider contract: expensive git compute must run off actor isolation.
        // A file-change batch with a cached snapshot is scoped to just the changed
        // paths and folded into the cache; everything else is a full status.
        let computeStart = envelopeClock.now
        let physicalCompletionGeneration = gitWorkingTreeProvider.physicalCompletionGeneration()
        let resolved = await resolveStatusResult(for: changeset)
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrentForPublication(changeset) else { return }
        guard case .available(let statusFacts) = resolved.result else {
            await handleUnavailableStatusResult(
                resolved.result.statusResult,
                physicalCompletionGeneration: physicalCompletionGeneration,
                changeset: changeset,
                computeStart: computeStart,
                scope: resolved.scope,
                pathspecCount: resolved.pathspecCount
            )
            return
        }
        let materialized = await materializeCompleteStatus(facts: statusFacts, changeset: changeset)
        guard !Task.isCancelled, !isShuttingDown, isCurrentForPublication(changeset) else { return }
        guard case .available(let statusSnapshot) = materialized.result else {
            await handleUnavailableStatusResult(
                materialized.result,
                physicalCompletionGeneration: materialized.capacityCompletionGeneration,
                changeset: changeset,
                computeStart: computeStart,
                scope: resolved.scope,
                pathspecCount: resolved.pathspecCount
            )
            return
        }
        await handleAvailableStatusResult(
            statusSnapshot,
            materialized: materialized,
            changeset: changeset,
            computeStart: computeStart,
            scope: resolved.scope,
            pathspecCount: resolved.pathspecCount
        )
    }

    private func handleUnavailableStatusResult(
        _ statusResult: GitWorkingTreeStatusResult,
        physicalCompletionGeneration: UInt64?,
        changeset: FileChangeset,
        computeStart: ContinuousClock.Instant,
        scope: GitStatusScope,
        pathspecCount: Int
    ) async {
        guard isCurrentForPublication(changeset) else { return }
        guard case .unavailable(let unavailable) = statusResult else { return }
        if unavailable.reason == .readCapacityExceeded || unavailable.reason == .readAlreadyInFlight {
            scheduleCapacityRetry(
                for: changeset,
                reason: unavailable.reason,
                afterPhysicalCompletionGeneration: physicalCompletionGeneration
            )
            if !capacityRetryWorktreeIds.contains(changeset.worktreeId) {
                closeRefreshFact(worktreeId: changeset.worktreeId, outcome: .capacityExceeded)
            }
            return
        }

        let statusCompletion = envelopeClock.now
        let statusDuration = computeStart.duration(to: statusCompletion)
        let statusOutcome: GitStatusOutcome
        let previousFailureCount = consecutiveStatusFailureCountByWorktreeId[changeset.worktreeId] ?? 0
        let consecutiveFailureCount = min(
            previousFailureCount + 1,
            AppPolicies.GitRefresh.statusUnavailableConsecutiveFailureThreshold
        )
        consecutiveStatusFailureCountByWorktreeId[changeset.worktreeId] = consecutiveFailureCount
        statusOutcome = unavailable.reason == .timeout ? .timeout : .unavailable
        performanceTraceRecorder?.recordDuration(
            .gitStatusUnavailable,
            duration: statusDuration,
            attributes: gitStatusCompletionTraceAttributes(
                for: changeset,
                unavailable: unavailable,
                context: GitStatusCompletionTraceContext(
                    scope: scope,
                    pathspecCount: pathspecCount,
                    statusCompletion: statusCompletion,
                    outcome: statusOutcome,
                    consecutiveFailureCount: consecutiveFailureCount,
                    statusDuration: statusDuration
                )
            )
        )
        guard !Task.isCancelled, !isShuttingDown else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrentForPublication(changeset) else { return }
        admissionStartedAtByWorktreeId.removeValue(forKey: changeset.worktreeId)
        if let requiredIntentGeneration =
            refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[changeset.worktreeId]
        {
            settleRepositoryRecomputationTarget(
                worktreeId: changeset.worktreeId,
                requiredIntentGeneration: requiredIntentGeneration,
                outcome: .failed
            )
        }
        openOrAdvanceStatusBackoff(for: changeset, reason: unavailable.reason)
        await emitGitWorkingDirectoryEvent(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            event: .statusOutcome(
                GitStatusOutcomeFact(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    outcome: statusOutcome,
                    reason: unavailable.reason,
                    consecutiveFailureCount: consecutiveFailureCount
                ))
        )
        closeRefreshFact(
            worktreeId: changeset.worktreeId,
            outcome: unavailable.reason == .timeout ? .timeout : .unavailable
        )
    }

}
