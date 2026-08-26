import AgentStudioGit
import AgentStudioInfrastructure
import Foundation

package struct RemoteReferenceAcceptance: Equatable, Sendable {
    package let repoId: UUID
    package let expectedOrigin: String
    package let topologyGeneration: UInt64
    package let authorityRevision: UInt64
    package let snapshot: GitRemoteTrackingSnapshot

    package init(
        repoId: UUID,
        expectedOrigin: String,
        topologyGeneration: UInt64,
        authorityRevision: UInt64,
        snapshot: GitRemoteTrackingSnapshot
    ) {
        self.repoId = repoId
        self.expectedOrigin = expectedOrigin
        self.topologyGeneration = topologyGeneration
        self.authorityRevision = authorityRevision
        self.snapshot = snapshot
    }
}

package actor RemoteReferenceRefreshActor {
    package typealias AuthorityUpdateHandler = @Sendable (RemoteReferenceAuthorityUpdate) async -> Void

    private let provider: any RemoteReferenceRefreshProviding
    private let onAuthorityUpdate: AuthorityUpdateHandler
    private let maximumConcurrentFetches: Int
    private let successfulResultFreshness: Duration
    private let automaticFailureBackoff: Duration
    private let monotonicNow: @Sendable () -> Duration
    private let delay: AsyncDelay
    private let performanceRecorder: (any RemoteReferencePerformanceRecording)?

    private var registrationsByRepoId: [UUID: RemoteReferenceRegistration] = [:]
    private var latestTopologyGenerationByRepoId: [UUID: UInt64] = [:]
    private var demandedRepositoryIds: Set<UUID> = []
    private var pendingRepositoryIds: Set<UUID> = []
    private var explicitRepositoryIds: Set<UUID> = []
    private var activeOperationsByRepoId: [UUID: RemoteReferenceActiveOperation] = [:]
    private var invalidatingRepositoryIds: Set<UUID> = []
    private var acceptedReferenceByRepoId: [UUID: RemoteReferenceAcceptance] = [:]
    private var lastSuccessfulFetchAtByRepoId: [UUID: Duration] = [:]
    private var failureDeadlineByRepoId: [UUID: Duration] = [:]
    private var currentnessRetryAtByRepoId: [UUID: Duration] = [:]
    private var cleanupDebtByRepoId: [UUID: GitStagedFetchHandle] = [:]
    private var cleanupRetryAtByRepoId: [UUID: Duration] = [:]
    private var deadlineTask: Task<Void, Never>?
    private var deadlineGeneration: UInt64 = 0
    private var authorityRevision: UInt64 = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var performanceAccumulator = RemoteReferencePerformanceAccumulator()
    private var lastRecordedSettlementSnapshot: RemoteReferencePerformanceSnapshot.Settlement?
    private var isShuttingDown = false

    package init(
        provider: any RemoteReferenceRefreshProviding = AgentStudioGitRemoteReferenceRefreshProvider(),
        maximumConcurrentFetches: Int = AppPolicies.RemoteReferenceRefresh.maximumConcurrentFetches,
        successfulResultFreshness: Duration = AppPolicies.RemoteReferenceRefresh.automaticFreshnessFloor,
        automaticFailureBackoff: Duration = AppPolicies.RemoteReferenceRefresh.automaticFailureRetryFloor,
        monotonicNow: @escaping @Sendable () -> Duration = {
            .seconds(ProcessInfo.processInfo.systemUptime)
        },
        sleepClock: (any Clock<Duration> & Sendable)? = nil,
        performanceRecorder: (any RemoteReferencePerformanceRecording)? = nil,
        onAuthorityUpdate: @escaping AuthorityUpdateHandler = { _ in }
    ) {
        precondition(maximumConcurrentFetches > 0)
        precondition(successfulResultFreshness > .zero)
        precondition(automaticFailureBackoff > .zero)
        self.provider = provider
        self.maximumConcurrentFetches = maximumConcurrentFetches
        self.successfulResultFreshness = successfulResultFreshness
        self.automaticFailureBackoff = automaticFailureBackoff
        self.monotonicNow = monotonicNow
        delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep
        self.performanceRecorder = performanceRecorder
        self.onAuthorityUpdate = onAuthorityUpdate
    }

    isolated deinit {
        deadlineTask?.cancel()
        for operation in activeOperationsByRepoId.values {
            switch operation {
            case .staging(_, let task): task.cancel()
            case .promoting(_, _, let task): task.cancel()
            }
        }
    }

    package func register(
        repoId: UUID,
        worktreeId: UUID,
        repositoryPath: URL,
        remoteName: String,
        expectedOrigin: String?
    ) async {
        guard !isShuttingDown else { return }
        if var registration = registrationsByRepoId[repoId] {
            let nextExpectedOrigin = expectedOrigin ?? registration.expectedOrigin
            let alreadyContainsWorktree = registration.worktreeIds.contains(worktreeId)
            let nextRepositoryPath = alreadyContainsWorktree ? repositoryPath : registration.repositoryPath
            guard
                registration.repositoryPath != nextRepositoryPath
                    || registration.remoteName != remoteName
                    || registration.expectedOrigin != nextExpectedOrigin
                    || !alreadyContainsWorktree
            else { return }

            let nextGeneration = nextTopologyGeneration(repoId: repoId)
            await invalidateAuthority(repoId: repoId, topologyGeneration: nextGeneration)
            await revokeActiveOperation(repoId: repoId)
            registration.repositoryPath = nextRepositoryPath
            registration.remoteName = remoteName
            registration.expectedOrigin = nextExpectedOrigin
            registration.topologyGeneration = nextGeneration
            registration.worktreeIds.insert(worktreeId)
            registrationsByRepoId[repoId] = registration
            lastSuccessfulFetchAtByRepoId.removeValue(forKey: repoId)
            failureDeadlineByRepoId.removeValue(forKey: repoId)
            currentnessRetryAtByRepoId.removeValue(forKey: repoId)
        } else {
            let nextGeneration = nextTopologyGeneration(repoId: repoId)
            registrationsByRepoId[repoId] = RemoteReferenceRegistration(
                repoId: repoId,
                repositoryPath: repositoryPath,
                remoteName: remoteName,
                expectedOrigin: expectedOrigin,
                topologyGeneration: nextGeneration,
                worktreeIds: [worktreeId]
            )
        }
        await establishLocalAcceptance(repoId: repoId)
        if demandedRepositoryIds.contains(repoId) {
            pendingRepositoryIds.insert(repoId)
        }
        admitPendingAttempts()
        rescheduleDeadline()
    }

    package func unregister(worktreeId: UUID, repoId: UUID) async {
        guard var registration = registrationsByRepoId[repoId], registration.worktreeIds.contains(worktreeId) else {
            return
        }
        let nextGeneration = nextTopologyGeneration(repoId: repoId)
        await invalidateAuthority(repoId: repoId, topologyGeneration: nextGeneration)
        await revokeActiveOperation(repoId: repoId)
        registration.worktreeIds.remove(worktreeId)
        registration.topologyGeneration = nextGeneration
        lastSuccessfulFetchAtByRepoId.removeValue(forKey: repoId)
        failureDeadlineByRepoId.removeValue(forKey: repoId)
        currentnessRetryAtByRepoId.removeValue(forKey: repoId)
        if registration.worktreeIds.isEmpty {
            registrationsByRepoId.removeValue(forKey: repoId)
            demandedRepositoryIds.remove(repoId)
            pendingRepositoryIds.remove(repoId)
            explicitRepositoryIds.remove(repoId)
        } else {
            registrationsByRepoId[repoId] = registration
            await establishLocalAcceptance(repoId: repoId)
            if demandedRepositoryIds.contains(repoId) {
                pendingRepositoryIds.insert(repoId)
            }
        }
        admitPendingAttempts()
        rescheduleDeadline()
    }

    package func unregister(worktreeId: UUID) async {
        guard
            let repoId = registrationsByRepoId.first(where: { _, registration in
                registration.worktreeIds.contains(worktreeId)
            })?.key
        else { return }
        await unregister(worktreeId: worktreeId, repoId: repoId)
    }

    package func assertTopology(_ contextsByWorktreeId: [UUID: WorktreeFilesystemContext]) async {
        guard !isShuttingDown else { return }
        let desiredEntriesByRepoId = Dictionary(
            grouping: contextsByWorktreeId.sorted(by: { $0.key.uuidString < $1.key.uuidString }),
            by: { $0.value.repoId }
        )
        let allRepoIds = Set(registrationsByRepoId.keys).union(desiredEntriesByRepoId.keys)
        for repoId in allRepoIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let desiredEntries = desiredEntriesByRepoId[repoId] else {
                guard registrationsByRepoId[repoId] != nil else { continue }
                let nextGeneration = nextTopologyGeneration(repoId: repoId)
                await invalidateAuthority(repoId: repoId, topologyGeneration: nextGeneration)
                await revokeActiveOperation(repoId: repoId)
                registrationsByRepoId.removeValue(forKey: repoId)
                demandedRepositoryIds.remove(repoId)
                pendingRepositoryIds.remove(repoId)
                explicitRepositoryIds.remove(repoId)
                lastSuccessfulFetchAtByRepoId.removeValue(forKey: repoId)
                failureDeadlineByRepoId.removeValue(forKey: repoId)
                currentnessRetryAtByRepoId.removeValue(forKey: repoId)
                continue
            }

            let currentRegistration = registrationsByRepoId[repoId]
            let desiredWorktreeIds = Set(desiredEntries.map(\.key))
            let representativePath =
                desiredEntries.first(where: { $0.value.rootPath == currentRegistration?.repositoryPath })?.value
                .rootPath
                ?? desiredEntries[0].value.rootPath
            if let currentRegistration,
                currentRegistration.repositoryPath == representativePath,
                currentRegistration.remoteName == "origin",
                currentRegistration.worktreeIds == desiredWorktreeIds
            {
                continue
            }

            let nextGeneration = nextTopologyGeneration(repoId: repoId)
            if currentRegistration != nil {
                await invalidateAuthority(repoId: repoId, topologyGeneration: nextGeneration)
                await revokeActiveOperation(repoId: repoId)
            }
            registrationsByRepoId[repoId] = RemoteReferenceRegistration(
                repoId: repoId,
                repositoryPath: representativePath,
                remoteName: "origin",
                expectedOrigin: currentRegistration?.expectedOrigin,
                topologyGeneration: nextGeneration,
                worktreeIds: desiredWorktreeIds
            )
            lastSuccessfulFetchAtByRepoId.removeValue(forKey: repoId)
            failureDeadlineByRepoId.removeValue(forKey: repoId)
            currentnessRetryAtByRepoId.removeValue(forKey: repoId)
            await establishLocalAcceptance(repoId: repoId)
            if demandedRepositoryIds.contains(repoId) {
                pendingRepositoryIds.insert(repoId)
            }
        }
        admitPendingAttempts()
        rescheduleDeadline()
    }

    package func setOrigin(repoId: UUID, expectedOrigin: String?) async {
        guard var registration = registrationsByRepoId[repoId], registration.expectedOrigin != expectedOrigin else {
            return
        }
        invalidatingRepositoryIds.insert(repoId)
        let nextGeneration = nextTopologyGeneration(repoId: repoId)
        await invalidateAuthority(repoId: repoId, topologyGeneration: nextGeneration)
        await revokeActiveOperation(repoId: repoId, alreadyInvalidating: true)
        registration.expectedOrigin = expectedOrigin
        registration.topologyGeneration = nextGeneration
        registrationsByRepoId[repoId] = registration
        lastSuccessfulFetchAtByRepoId.removeValue(forKey: repoId)
        failureDeadlineByRepoId.removeValue(forKey: repoId)
        currentnessRetryAtByRepoId.removeValue(forKey: repoId)
        invalidatingRepositoryIds.remove(repoId)
        await establishLocalAcceptance(repoId: repoId)
        if expectedOrigin != nil, demandedRepositoryIds.contains(repoId) {
            pendingRepositoryIds.insert(repoId)
        }
        admitPendingAttempts()
        rescheduleDeadline()
    }

    package func setDemand(repositoryIds: Set<UUID>) async {
        guard !isShuttingDown, repositoryIds != demandedRepositoryIds else { return }
        performanceAccumulator.increment(\.demandChanged)
        if repositoryIds.isEmpty {
            performanceAccumulator.increment(\.demandCleared)
        }
        let removedRepositoryIds = demandedRepositoryIds.subtracting(repositoryIds)
        demandedRepositoryIds = repositoryIds
        pendingRepositoryIds.subtract(removedRepositoryIds)
        explicitRepositoryIds.subtract(removedRepositoryIds)
        for repoId in removedRepositoryIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            currentnessRetryAtByRepoId.removeValue(forKey: repoId)
            await revokeActiveOperation(repoId: repoId)
        }
        pendingRepositoryIds.formUnion(repositoryIds.filter { registrationsByRepoId[$0] != nil })
        admitPendingAttempts()
        rescheduleDeadline()
        flushPerformanceSnapshot()
    }

    package func refresh(repoId: UUID) {
        guard !isShuttingDown, demandedRepositoryIds.contains(repoId), registrationsByRepoId[repoId] != nil else {
            return
        }
        explicitRepositoryIds.insert(repoId)
        pendingRepositoryIds.insert(repoId)
        admitPendingAttempts()
        rescheduleDeadline()
    }

    package func waitUntilIdle() async {
        guard hasOutstandingPhysicalWork else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    package func shutdown() async {
        guard !isShuttingDown else {
            await waitUntilIdle()
            return
        }
        isShuttingDown = true
        deadlineGeneration &+= 1
        deadlineTask?.cancel()
        deadlineTask = nil
        demandedRepositoryIds.removeAll()
        pendingRepositoryIds.removeAll()
        explicitRepositoryIds.removeAll()
        for repoId in activeOperationsByRepoId.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            await revokeActiveOperation(repoId: repoId)
        }
        for repoId in cleanupDebtByRepoId.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            await retryCleanupDebt(repoId: repoId)
        }
        acceptedReferenceByRepoId.removeAll()
        resumeIdleWaitersIfNeeded()
        flushPerformanceSnapshot()
    }

    private var hasOutstandingPhysicalWork: Bool {
        !activeOperationsByRepoId.isEmpty
    }

    private func establishLocalAcceptance(repoId: UUID) async {
        guard !isShuttingDown, !invalidatingRepositoryIds.contains(repoId),
            let registration = registrationsByRepoId[repoId]
        else { return }
        do {
            guard let expectedOrigin = registration.expectedOrigin else { return }
            let snapshot = try await provider.captureRemoteTrackingSnapshot(
                repositoryPath: registration.repositoryPath,
                remoteName: registration.remoteName
            )
            guard snapshot.configuredRemoteURL == expectedOrigin,
                accepts(registration: registration)
            else { return }
            do {
                try await provider.cleanupAbandonedStagedFetches(
                    repositoryCommonDirectory: snapshot.repositoryCommonDirectory,
                    retainedStagingIds: activeStagingIds(
                        repoId: repoId,
                        repositoryCommonDirectory: snapshot.repositoryCommonDirectory
                    )
                )
            } catch {
                // Recovery cleanup is independent of otherwise valid local authority.
            }
            guard accepts(registration: registration) else { return }
            let acceptance = RemoteReferenceAcceptance(
                repoId: repoId,
                expectedOrigin: expectedOrigin,
                topologyGeneration: registration.topologyGeneration,
                authorityRevision: nextAuthorityRevision(),
                snapshot: snapshot
            )
            acceptedReferenceByRepoId[repoId] = acceptance
            performanceAccumulator.increment(\.publicationLocalAccepted)
            await onAuthorityUpdate(.localAccepted(acceptance))
        } catch {
            // Registration remains valid; demanded refresh owns bounded recovery.
        }
    }

    private func admitPendingAttempts() {
        guard !isShuttingDown else { return }
        let now = monotonicNow()
        while activeOperationsByRepoId.count < maximumConcurrentFetches {
            guard
                let repoId =
                    pendingRepositoryIds
                    .filter({ activeOperationsByRepoId[$0] == nil && isEligible(repoId: $0, now: now) })
                    .min(by: { $0.uuidString < $1.uuidString }),
                let registration = registrationsByRepoId[repoId],
                let expectedOrigin = registration.expectedOrigin,
                demandedRepositoryIds.contains(repoId),
                !invalidatingRepositoryIds.contains(repoId)
            else { break }
            pendingRepositoryIds.remove(repoId)
            currentnessRetryAtByRepoId.removeValue(forKey: repoId)
            let attempt = RemoteReferenceAttempt(
                repoId: repoId,
                repositoryPath: registration.repositoryPath,
                remoteName: registration.remoteName,
                expectedOrigin: expectedOrigin,
                topologyGeneration: registration.topologyGeneration,
                stagingId: UUIDv7.generate()
            )
            let task = Task { [provider] in
                await Self.performStaging(attempt, provider: provider)
            }
            activeOperationsByRepoId[repoId] = .staging(attempt, task)
            performanceAccumulator.increment(\.admissionAdmitted)
            performanceAccumulator.increment(\.stagingStarted)
            Task { [weak self] in
                let outcome = await task.value
                await self?.finishStaging(outcome)
            }
        }
        if activeOperationsByRepoId.count >= maximumConcurrentFetches,
            pendingRepositoryIds.contains(where: { activeOperationsByRepoId[$0] == nil })
        {
            performanceAccumulator.increment(\.admissionCapacityDeferred)
        }
        rescheduleDeadline()
        resumeIdleWaitersIfNeeded()
        flushPerformanceSnapshot()
    }

    private func isEligible(repoId: UUID, now: Duration) -> Bool {
        guard demandedRepositoryIds.contains(repoId), registrationsByRepoId[repoId] != nil else { return false }
        guard cleanupDebtByRepoId[repoId] == nil else { return false }
        if let currentnessRetryAt = currentnessRetryAtByRepoId[repoId], currentnessRetryAt > now {
            return false
        }
        if let failureDeadline = failureDeadlineByRepoId[repoId], failureDeadline > now {
            return false
        }
        if explicitRepositoryIds.contains(repoId) {
            return true
        }
        guard let lastSuccessfulFetchAt = lastSuccessfulFetchAtByRepoId[repoId] else { return true }
        return lastSuccessfulFetchAt + successfulResultFreshness <= now
    }

    private nonisolated static func performStaging(
        _ attempt: RemoteReferenceAttempt,
        provider: any RemoteReferenceRefreshProviding
    ) async -> RemoteReferenceStagingOutcome {
        do {
            let snapshot = try await provider.captureRemoteTrackingSnapshot(
                repositoryPath: attempt.repositoryPath,
                remoteName: attempt.remoteName
            )
            guard snapshot.configuredRemoteURL == attempt.expectedOrigin else {
                return .obsolete(attempt)
            }
            let stagedFetch = try await provider.stageFetch(snapshot: snapshot, stagingId: attempt.stagingId)
            return .staged(attempt, stagedFetch)
        } catch is CancellationError {
            return .obsolete(attempt)
        } catch {
            return .failed(attempt)
        }
    }

    private func finishStaging(_ outcome: RemoteReferenceStagingOutcome) async {
        let attempt = outcome.attempt
        guard !invalidatingRepositoryIds.contains(attempt.repoId),
            case .staging(let activeAttempt, _) = activeOperationsByRepoId[attempt.repoId],
            activeAttempt.stagingId == attempt.stagingId
        else { return }
        performanceAccumulator.increment(\.stagingCompleted)
        switch outcome {
        case .failed:
            finishFailedAttempt(attempt)
        case .obsolete:
            performanceAccumulator.increment(\.validationObsolete)
            finishObsoleteAttempt(attempt)
        case .staged(_, let stagedFetch):
            guard accepts(attempt) else {
                performanceAccumulator.increment(\.validationObsolete)
                await recordCleanup(stagedFetch.handle, repoId: attempt.repoId)
                finishObsoleteAttempt(attempt)
                return
            }
            performanceAccumulator.increment(\.validationCurrent)
            let task = Task { [provider] in
                await Self.performPromotion(attempt, stagedFetch: stagedFetch, provider: provider)
            }
            activeOperationsByRepoId[attempt.repoId] = .promoting(attempt, stagedFetch, task)
            performanceAccumulator.increment(\.promotionStarted)
            Task { [weak self] in
                let promotionOutcome = await task.value
                await self?.finishPromotion(promotionOutcome)
            }
        }
    }

    private nonisolated static func performPromotion(
        _ attempt: RemoteReferenceAttempt,
        stagedFetch: GitStagedFetchResult,
        provider: any RemoteReferenceRefreshProviding
    ) async -> RemoteReferencePromotionOutcome {
        do {
            try await provider.promoteStagedFetch(stagedFetch)
            return .promoted(attempt, stagedFetch)
        } catch {
            return .failed(attempt, stagedFetch)
        }
    }

    private func finishPromotion(_ outcome: RemoteReferencePromotionOutcome) async {
        let attempt = outcome.attempt
        guard !invalidatingRepositoryIds.contains(attempt.repoId),
            case .promoting(let activeAttempt, _, _) = activeOperationsByRepoId[attempt.repoId],
            activeAttempt.stagingId == attempt.stagingId
        else { return }
        performanceAccumulator.increment(\.promotionCompleted)

        await recordCleanup(outcome.stagedFetch.handle, repoId: attempt.repoId)
        switch outcome {
        case .failed:
            finishFailedAttempt(attempt)
        case .promoted(_, let stagedFetch):
            guard accepts(attempt), let registration = registrationsByRepoId[attempt.repoId] else {
                performanceAccumulator.increment(\.validationObsolete)
                finishObsoleteAttempt(attempt)
                return
            }
            performanceAccumulator.increment(\.validationCurrent)
            let acceptance = RemoteReferenceAcceptance(
                repoId: attempt.repoId,
                expectedOrigin: attempt.expectedOrigin,
                topologyGeneration: attempt.topologyGeneration,
                authorityRevision: nextAuthorityRevision(),
                snapshot: stagedFetch.snapshot
            )
            acceptedReferenceByRepoId[attempt.repoId] = acceptance
            lastSuccessfulFetchAtByRepoId[attempt.repoId] = monotonicNow()
            failureDeadlineByRepoId.removeValue(forKey: attempt.repoId)
            currentnessRetryAtByRepoId.removeValue(forKey: attempt.repoId)
            explicitRepositoryIds.remove(attempt.repoId)
            activeOperationsByRepoId.removeValue(forKey: attempt.repoId)
            performanceAccumulator.increment(\.publicationPromoted)
            await onAuthorityUpdate(
                .promoted(acceptance, representedWorktreeIds: registration.worktreeIds)
            )
            admitPendingAttempts()
            flushPerformanceSnapshot()
        }
    }

    private func finishFailedAttempt(_ attempt: RemoteReferenceAttempt) {
        guard activeOperationsByRepoId[attempt.repoId]?.attempt.stagingId == attempt.stagingId else { return }
        activeOperationsByRepoId.removeValue(forKey: attempt.repoId)
        performanceAccumulator.increment(\.executionFailed)
        explicitRepositoryIds.remove(attempt.repoId)
        currentnessRetryAtByRepoId.removeValue(forKey: attempt.repoId)
        if demandedRepositoryIds.contains(attempt.repoId) {
            failureDeadlineByRepoId[attempt.repoId] = monotonicNow() + automaticFailureBackoff
        }
        rescheduleDeadline()
        admitPendingAttempts()
        flushPerformanceSnapshot()
    }

    private func finishObsoleteAttempt(_ attempt: RemoteReferenceAttempt) {
        guard activeOperationsByRepoId[attempt.repoId]?.attempt.stagingId == attempt.stagingId else { return }
        activeOperationsByRepoId.removeValue(forKey: attempt.repoId)
        if demandedRepositoryIds.contains(attempt.repoId), registrationsByRepoId[attempt.repoId] != nil {
            pendingRepositoryIds.insert(attempt.repoId)
            currentnessRetryAtByRepoId[attempt.repoId] =
                monotonicNow() + AppPolicies.RemoteReferenceRefresh.capacityRecheckDelay
        }
        rescheduleDeadline()
        admitPendingAttempts()
        flushPerformanceSnapshot()
    }

    private func revokeActiveOperation(repoId: UUID, alreadyInvalidating: Bool = false) async {
        let insertedInvalidation = alreadyInvalidating ? false : invalidatingRepositoryIds.insert(repoId).inserted
        defer {
            if insertedInvalidation {
                invalidatingRepositoryIds.remove(repoId)
            }
        }
        guard let operation = activeOperationsByRepoId[repoId] else { return }
        performanceAccumulator.increment(\.executionCancelled)
        switch operation {
        case .staging(_, let task):
            task.cancel()
            let outcome = await task.value
            if case .staged(_, let stagedFetch) = outcome {
                await recordCleanup(stagedFetch.handle, repoId: repoId)
            }
        case .promoting(_, let stagedFetch, let task):
            task.cancel()
            let cleanupTask = Task { [provider] in
                try await provider.cleanupStagedFetch(stagedFetch.handle)
            }
            _ = await task.value
            do {
                try await cleanupTask.value
                cleanupDebtByRepoId.removeValue(forKey: repoId)
                cleanupRetryAtByRepoId.removeValue(forKey: repoId)
            } catch {
                cleanupDebtByRepoId[repoId] = stagedFetch.handle
                cleanupRetryAtByRepoId[repoId] =
                    monotonicNow() + AppPolicies.RemoteReferenceRefresh.capacityRecheckDelay
            }
        }
        activeOperationsByRepoId.removeValue(forKey: repoId)
        resumeIdleWaitersIfNeeded()
        flushPerformanceSnapshot()
    }

    private func recordCleanup(_ handle: GitStagedFetchHandle, repoId: UUID) async {
        do {
            try await provider.cleanupStagedFetch(handle)
            performanceAccumulator.increment(\.cleanupSucceeded)
            cleanupDebtByRepoId.removeValue(forKey: repoId)
            cleanupRetryAtByRepoId.removeValue(forKey: repoId)
        } catch {
            performanceAccumulator.increment(\.cleanupFailed)
            cleanupDebtByRepoId[repoId] = handle
            cleanupRetryAtByRepoId[repoId] =
                monotonicNow() + AppPolicies.RemoteReferenceRefresh.capacityRecheckDelay
        }
        rescheduleDeadline()
    }

    private func retryCleanupDebt(repoId: UUID) async {
        guard let handle = cleanupDebtByRepoId[repoId] else { return }
        await recordCleanup(handle, repoId: repoId)
    }

    private func accepts(_ attempt: RemoteReferenceAttempt) -> Bool {
        guard !isShuttingDown, !invalidatingRepositoryIds.contains(attempt.repoId),
            demandedRepositoryIds.contains(attempt.repoId),
            let registration = registrationsByRepoId[attempt.repoId]
        else { return false }
        return registration.topologyGeneration == attempt.topologyGeneration
            && registration.expectedOrigin == attempt.expectedOrigin
            && registration.repositoryPath == attempt.repositoryPath
            && registration.remoteName == attempt.remoteName
    }

    private func accepts(registration: RemoteReferenceRegistration) -> Bool {
        guard let current = registrationsByRepoId[registration.repoId] else { return false }
        return current.topologyGeneration == registration.topologyGeneration
            && current.expectedOrigin == registration.expectedOrigin
            && current.repositoryPath == registration.repositoryPath
            && current.remoteName == registration.remoteName
    }

    private func nextTopologyGeneration(repoId: UUID) -> UInt64 {
        let nextGeneration = (latestTopologyGenerationByRepoId[repoId] ?? 0) &+ 1
        latestTopologyGenerationByRepoId[repoId] = nextGeneration
        return nextGeneration
    }

    private func nextAuthorityRevision() -> UInt64 {
        authorityRevision &+= 1
        return authorityRevision
    }

    private func invalidateAuthority(repoId: UUID, topologyGeneration: UInt64) async {
        acceptedReferenceByRepoId.removeValue(forKey: repoId)
        performanceAccumulator.increment(\.publicationInvalidated)
        await onAuthorityUpdate(
            .invalidated(
                repoId: repoId,
                topologyGeneration: topologyGeneration,
                authorityRevision: nextAuthorityRevision()
            )
        )
    }

    package func flushPerformanceSnapshot() {
        let settlementSnapshot = currentSettlementSnapshot()
        let changedSettlementSnapshot =
            settlementSnapshot == lastRecordedSettlementSnapshot ? nil : settlementSnapshot
        lastRecordedSettlementSnapshot = settlementSnapshot
        let snapshot = performanceAccumulator.takeSnapshot(settlement: changedSettlementSnapshot)
        guard !snapshot.isEmpty else { return }
        performanceRecorder?.recordRemoteReferencePerformanceSnapshot(snapshot)
    }

    private func currentSettlementSnapshot() -> RemoteReferencePerformanceSnapshot.Settlement {
        let now = monotonicNow()
        let activeRepositoryIds = Set(activeOperationsByRepoId.keys)
        var pendingFuture = 0
        var pendingReady = 0
        var pendingCapacity = 0
        var pendingActiveFollowUp = 0
        var pendingUnclassified = 0

        for repoId in pendingRepositoryIds {
            if activeRepositoryIds.contains(repoId) {
                pendingActiveFollowUp += 1
            } else if pendingFutureDeadline(repoId: repoId, now: now) != nil {
                pendingFuture += 1
            } else if isEligible(repoId: repoId, now: now) {
                if activeOperationsByRepoId.count >= maximumConcurrentFetches {
                    pendingCapacity += 1
                } else {
                    pendingReady += 1
                }
            } else {
                pendingUnclassified += 1
            }
        }

        let deadlines = deadlineCandidates(now: now)
        let nextDeadline = deadlines.filter { $0 > now }.min()
        return RemoteReferencePerformanceSnapshot.Settlement(
            physicalActive: UInt64(clamping: activeOperationsByRepoId.count),
            pendingTotal: UInt64(clamping: pendingRepositoryIds.count),
            pendingFuture: UInt64(clamping: pendingFuture),
            pendingReady: UInt64(clamping: pendingReady),
            pendingCapacity: UInt64(clamping: pendingCapacity),
            pendingActiveFollowUp: UInt64(clamping: pendingActiveFollowUp),
            pendingUnclassified: UInt64(clamping: pendingUnclassified),
            deadlineOverdue: UInt64(clamping: deadlines.count { $0 <= now }),
            deadlineNextMilliseconds: nextDeadline.map {
                AgentStudioPerformanceTraceRecorder.milliseconds(from: max(.zero, $0 - now))
            } ?? 0
        )
    }

    private func pendingFutureDeadline(repoId: UUID, now: Duration) -> Duration? {
        var deadlines: [Duration] = []
        if let cleanupRetryAt = cleanupRetryAtByRepoId[repoId], cleanupRetryAt > now {
            deadlines.append(cleanupRetryAt)
        }
        if demandedRepositoryIds.contains(repoId), registrationsByRepoId[repoId] != nil,
            let currentnessRetryAt = currentnessRetryAtByRepoId[repoId], currentnessRetryAt > now
        {
            deadlines.append(currentnessRetryAt)
        }
        if let failureDeadline = failureDeadlineByRepoId[repoId], failureDeadline > now {
            deadlines.append(failureDeadline)
        }
        if let lastSuccessfulFetchAt = lastSuccessfulFetchAtByRepoId[repoId] {
            let freshnessDeadline = lastSuccessfulFetchAt + successfulResultFreshness
            if freshnessDeadline > now {
                deadlines.append(freshnessDeadline)
            }
        }
        return deadlines.min()
    }

    private func activeStagingIds(
        repoId: UUID,
        repositoryCommonDirectory: URL
    ) -> Set<UUID> {
        Set(
            activeOperationsByRepoId.compactMap { activeRepoId, operation in
                switch operation {
                case .staging(let attempt, _):
                    return activeRepoId == repoId ? attempt.stagingId : nil
                case .promoting(_, let stagedFetch, _):
                    return stagedFetch.handle.repositoryCommonDirectory == repositoryCommonDirectory
                        ? stagedFetch.handle.stagingID
                        : nil
                }
            }
        )
    }

    private func rescheduleDeadline() {
        deadlineGeneration &+= 1
        let generation = deadlineGeneration
        deadlineTask?.cancel()
        deadlineTask = nil
        guard !isShuttingDown else { return }
        let now = monotonicNow()
        let deadlines = deadlineCandidates(now: now)
        guard let earliest = deadlines.min() else { return }
        let wait = max(.zero, earliest - now)
        let delay = self.delay
        deadlineTask = Task { [weak self, delay] in
            do {
                try await delay.wait(wait)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.deadlineDidFire(generation: generation)
        }
    }

    private func deadlineCandidates(now: Duration) -> [Duration] {
        var deadlines = cleanupRetryAtByRepoId.values.map { $0 }
        deadlines.append(
            contentsOf: currentnessRetryAtByRepoId.compactMap { repoId, deadline in
                demandedRepositoryIds.contains(repoId) && registrationsByRepoId[repoId] != nil
                    ? deadline
                    : nil
            })
        deadlines.append(
            contentsOf: demandedRepositoryIds.compactMap { repoId -> Duration? in
                guard activeOperationsByRepoId[repoId] == nil, registrationsByRepoId[repoId] != nil else { return nil }
                if let failureDeadline = failureDeadlineByRepoId[repoId], failureDeadline > now {
                    return failureDeadline
                }
                guard let lastSuccessfulFetchAt = lastSuccessfulFetchAtByRepoId[repoId] else { return nil }
                let freshnessDeadline = lastSuccessfulFetchAt + successfulResultFreshness
                return freshnessDeadline > now ? freshnessDeadline : nil
            })
        return deadlines
    }

    private func deadlineDidFire(generation: UInt64) async {
        guard generation == deadlineGeneration, !isShuttingDown else { return }
        deadlineTask = nil
        let now = monotonicNow()
        for repoId in currentnessRetryAtByRepoId.keys
        where currentnessRetryAtByRepoId[repoId].map({ $0 <= now }) == true {
            currentnessRetryAtByRepoId.removeValue(forKey: repoId)
        }
        for repoId in cleanupRetryAtByRepoId.keys.sorted(by: { $0.uuidString < $1.uuidString })
        where cleanupRetryAtByRepoId[repoId].map({ $0 <= now }) == true {
            await retryCleanupDebt(repoId: repoId)
        }
        for repoId in demandedRepositoryIds where isEligible(repoId: repoId, now: now) {
            pendingRepositoryIds.insert(repoId)
        }
        admitPendingAttempts()
        rescheduleDeadline()
    }

    private func resumeIdleWaitersIfNeeded() {
        guard !hasOutstandingPhysicalWork else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
