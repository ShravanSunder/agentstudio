import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

extension WorkspaceCacheCoordinator {
    func waitForRetentionCommit() async {
        while isCollectingRetainedLocations {
            await withCheckedContinuation { retentionMutationWaiters.append($0) }
        }
    }

    func rescheduleRepositoryRetention(minimumDelay: Duration = .zero) async {
        guard topologyPersistence != nil, !retentionIsShuttingDown else { return }
        let input = workspaceStore.mutationCoordinator.captureRepositoryLifecycleInput()
        let time = try? await retentionNow()
        let delay = await RepositoryRetentionPreparation.nextDelay(input, at: time)
        let cleanupPending = await topologyPersistence?.hasPendingLocalCleanup() ?? false
        guard input.revision == workspaceStore.repositoryTopologyAtom.lifecycleRevision else { return }
        await retentionScheduler.schedule(
            after: delay.map { max(minimumDelay, $0) }
                ?? (cleanupPending ? AppPolicies.RepositoryRetention.retryDelay : nil))
    }

    func collectRetainedRepositories() async {
        guard let persistence = topologyPersistence, !retentionIsShuttingDown, !retentionValidationInFlight else {
            return
        }
        retentionValidationInFlight = true
        defer { retentionValidationInFlight = false }
        for _ in 0..<AppPolicies.RepositoryRetention.reconciliationRetryLimit {
            let topology = workspaceStore.repositoryTopologyAtom
            let validationInput = workspaceStore.mutationCoordinator.captureRepositoryLifecycleInput()
            guard let validationTime = try? await retentionNow() else { break }
            let scopeIDs = await RepositoryRetentionPreparation.validationScopeIDs(validationInput, at: validationTime)
            guard validationInput.revision == topology.lifecycleRevision else { continue }
            guard !scopeIDs.isEmpty else { break }
            let receipts = await refreshRetentionScopes(
                topology.watchedPaths, topology.repos, topology.worktreePathIndexGeneration, scopeIDs)
            for receipt in receipts {
                await consumeWatchedFolderObservation(receipt.observation, sequence: receipt.sequence)
            }
            let input = workspaceStore.mutationCoordinator.captureRepositoryLifecycleInput()
            var currentObservations: [WatchedFolderTopologyObservation] = []
            for receipt in receipts {
                if appliedScopeSequences[receipt.observation.registration.sourceID] == receipt.sequence,
                    await validateSourceObservations([receipt.observation])
                {
                    currentObservations.append(receipt.observation)
                }
            }
            guard let time = try? await retentionNow(),
                let unsettledKeys = try? await persistence.unsettledRepositoryRetentionKeys()
            else { break }
            let candidates = await RepositoryRetentionPreparation.candidates(
                input, observations: currentObservations, at: time,
                excludingRepositoryKeys: unsettledKeys, performanceTraceRecorder: performanceTraceRecorder)
            guard input.revision == topology.lifecycleRevision else { continue }
            guard !candidates.isEmpty else { break }
            isCollectingRetainedLocations = true
            // Reserve first, then validate all dependent sources in one actor operation. A source
            // superseded during preparation cannot reach SQL with an obsolete absence receipt.
            guard await validateSourceObservations(currentObservations), input.revision == topology.lifecycleRevision
            else {
                releaseRetentionReservation()
                continue
            }
            let commitStart = ContinuousClock.now
            do {
                let committed = try await persistence.collect(candidates, expectedRevision: input.revision, at: time)
                let publicationStart = ContinuousClock.now
                guard workspaceStore.mutationCoordinator.applyRepositoryLifecycleChange(committed) else {
                    preconditionFailure("Retention reservation must serialize canonical topology publication")
                }
                for worktreeID in candidates.worktreeAbsences.keys { repoCache.removeWorktree(worktreeID) }
                for repositoryID in candidates.repositoryAbsences.keys { repoCache.removeRepo(repositoryID) }
                refreshTraceIdentity()
                performanceTraceRecorder?.recordDuration(
                    .repositoryRetentionCommit,
                    duration: commitStart.duration(to: .now),
                    attributes: [
                        "agentstudio.performance.repository_lifecycle.collected_location.count": .int(candidates.count),
                        "agentstudio.performance.repository_lifecycle.mainactor_held_ms": .double(
                            AgentStudioPerformanceTraceRecorder.milliseconds(from: publicationStart.duration(to: .now))),
                    ])
                Self.logger.info("Repository retention committed locations=\(candidates.count, privacy: .public)")
            } catch {
                Self.logger.warning("Repository retention deferred after transaction admission failure")
            }
            releaseRetentionReservation()
            break
        }
        // Each operation is bounded. A subsequent deadline/startup resumes cleanup after failure or process exit.
        var cleanup = await persistence.reconcileLocalOrphans()
        while cleanup == .progress {
            await Task.yield()
            cleanup = await persistence.reconcileLocalOrphans()
        }
        if cleanup == .unavailable {
            await retentionScheduler.schedule(after: AppPolicies.RepositoryRetention.retryDelay)
        } else {
            await rescheduleRepositoryRetention(minimumDelay: AppPolicies.RepositoryRetention.retryDelay)
        }
    }

    private func releaseRetentionReservation() {
        isCollectingRetainedLocations = false
        let queued = deferredTopologyActions
        deferredTopologyActions.removeAll()
        for action in queued { action() }
        let waiters = retentionMutationWaiters
        retentionMutationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
