import AgentStudioInfrastructure
import Foundation
import os

package actor ForgeActor {
    private struct WorktreeMembership: Sendable {
        let repoId: UUID
        let rootPath: URL
        var branch: String?
    }

    private static let logger = Logger(subsystem: "com.agentstudio", category: "ForgeActor")

    private let runtimeBus: EventBus<RuntimeEnvelope>
    private let statusProvider: any ForgeStatusProvider
    private let providerName: String
    private let envelopeClock: ContinuousClock
    let monotonicNow: @Sendable () -> Duration
    private let delay: AsyncDelay
    private let subscriptionBufferLimit: Int
    let maximumConcurrentProviderRequests: Int
    let performanceTraceRecorder: (any ForgePerformanceRecording)?
    private let beforeEventEmission: (@Sendable (ForgeEvent) async -> Void)?

    private var subscriptionTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    var providerTasksByRequestId: [UInt64: Task<Void, Never>] = [:]
    var providerRepoIdByRequestId: [UInt64: UUID] = [:]
    private var nextDeadlineGeneration: UInt64 = 0
    private var nextProviderRequestId: UInt64 = 0
    private var nextEnvelopeSequence: UInt64 = 0
    private var membershipByWorktreeId: [UUID: WorktreeMembership] = [:]
    private var demandedWorktreeIds: Set<UUID> = []
    var refreshStateByRepoId: [UUID: RepositoryRefreshState] = [:]
    var performanceAccumulator = ForgePerformanceAccumulator()
    var lastRecordedSettlementSnapshot: ForgePerformanceSnapshot.Settlement?
    var isShuttingDown = false

    package init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        statusProvider: any ForgeStatusProvider,
        providerName: String = "github",
        envelopeClock: ContinuousClock = ContinuousClock(),
        monotonicNow: @escaping @Sendable () -> Duration = {
            .seconds(ProcessInfo.processInfo.systemUptime)
        },
        sleepClock: (any Clock<Duration> & Sendable)? = nil,
        subscriptionBufferLimit: Int = 256,
        maximumConcurrentProviderRequests: Int =
            AppPolicies.ForgeRefresh.maximumConcurrentProviderRequests,
        performanceTraceRecorder: (any ForgePerformanceRecording)? = nil,
        beforeEventEmission: (@Sendable (ForgeEvent) async -> Void)? = nil
    ) {
        runtimeBus = bus
        self.statusProvider = statusProvider
        self.providerName = providerName
        self.envelopeClock = envelopeClock
        self.monotonicNow = monotonicNow
        delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep
        self.subscriptionBufferLimit = subscriptionBufferLimit
        self.maximumConcurrentProviderRequests = max(1, maximumConcurrentProviderRequests)
        self.performanceTraceRecorder = performanceTraceRecorder
        self.beforeEventEmission = beforeEventEmission
    }

    isolated deinit {
        subscriptionTask?.cancel()
        deadlineTask?.cancel()
        for task in providerTasksByRequestId.values {
            task.cancel()
        }
    }

    package func start() async {
        guard subscriptionTask == nil else { return }
        let stream = await runtimeBus.subscribe(
            policy: .lossyNewest(subscriptionBufferLimit),
            subscriberName: "ForgeActor",
            factInterest: .matching([.worktreeGitWorkingDirectory])
        )
        subscriptionTask = Task { [weak self] in
            for await runtimeEnvelope in stream {
                guard !Task.isCancelled, let self else { return }
                await self.handleIncomingRuntimeEnvelope(runtimeEnvelope)
            }
        }
        flushPerformanceSnapshot()
    }

    package func register(
        worktreeId: UUID,
        repoId: UUID,
        rootPath: URL,
        branch: String? = nil
    ) async {
        defer { flushPerformanceSnapshot() }
        let normalizedBranch = ForgePresentationFacts.normalizedBranch(branch)
        let priorMembership = membershipByWorktreeId[worktreeId]
        membershipByWorktreeId[worktreeId] = WorktreeMembership(
            repoId: repoId,
            rootPath: rootPath.standardizedFileURL,
            branch: normalizedBranch
        )

        if let priorMembership,
            priorMembership.repoId != repoId || priorMembership.branch != normalizedBranch
        {
            await invalidateBranchIfUnrepresented(
                repoId: priorMembership.repoId,
                branch: priorMembership.branch
            )
        }
        await requestRefreshIfDemanded(repoId: repoId, trigger: .automatic, correlationId: nil)
        rescheduleDeadline()
    }

    package func unregister(worktreeId: UUID) async {
        guard let removedMembership = membershipByWorktreeId.removeValue(forKey: worktreeId) else { return }
        defer { flushPerformanceSnapshot() }
        demandedWorktreeIds.remove(worktreeId)
        await invalidateBranchIfUnrepresented(
            repoId: removedMembership.repoId,
            branch: removedMembership.branch
        )
        await requestRefreshIfDemanded(
            repoId: removedMembership.repoId,
            trigger: .automatic,
            correlationId: nil
        )
        rescheduleDeadline()
    }

    package func setOrigin(repo repoId: UUID, remote: String) async {
        guard let normalizedOrigin = remote.trimmedNonEmpty else {
            await clearOrigin(repoId: repoId)
            return
        }

        var state = refreshStateByRepoId[repoId] ?? RepositoryRefreshState()
        guard state.origin != normalizedOrigin else { return }
        defer { flushPerformanceSnapshot() }
        let replacedExistingOrigin = state.origin != nil

        cancelProviderRequest(repoId: repoId)
        state.generation &+= 1
        state.origin = normalizedOrigin
        state.lastSuccessfulRefreshAt = nil
        state.lastAttemptAt = nil
        state.backoffUntil = nil
        state.activeRequestId = nil
        state.pendingFollowUp = false
        state.pendingFollowUpRequiresRefresh = false
        state.pendingFollowUpHasUnconfirmedScopeChange = false
        state.pendingFollowUpEligibleAt = nil
        state.consecutiveFailureCount = 0
        state.consecutiveUnsuccessfulAttempts = 0
        state.hasEmittedUnavailable = false
        state.stablePresentation = .unknown
        let originResetProjection = PullRequestRepositoryProjection.stable(.unknown)
        let shouldEmitOriginReset = state.acceptedProjection != originResetProjection
        state.acceptedProjection = originResetProjection
        refreshStateByRepoId[repoId] = state

        if replacedExistingOrigin, shouldEmitOriginReset {
            await emitForgeEvent(
                repoId: repoId,
                correlationId: nil,
                event: .pullRequestRepositoryProjectionChanged(
                    repoId: repoId,
                    projection: originResetProjection,
                    invalidatedBranches: []
                )
            )
        }
        await requestRefreshIfDemanded(repoId: repoId, trigger: .automatic, correlationId: nil)
        rescheduleDeadline()
    }

    package func removeRepository(repo repoId: UUID) async {
        defer { flushPerformanceSnapshot() }
        cancelProviderRequest(repoId: repoId)
        refreshStateByRepoId.removeValue(forKey: repoId)
        let removedWorktreeIds = Set(
            membershipByWorktreeId.compactMap { worktreeId, membership in
                membership.repoId == repoId ? worktreeId : nil
            }
        )
        for worktreeId in removedWorktreeIds {
            membershipByWorktreeId.removeValue(forKey: worktreeId)
        }
        demandedWorktreeIds.subtract(removedWorktreeIds)
        await emitForgeEvent(
            repoId: repoId,
            correlationId: nil,
            event: .pullRequestRepositoryProjectionChanged(
                repoId: repoId,
                projection: .stable(.unknown),
                invalidatedBranches: []
            )
        )
        rescheduleDeadline()
    }

    package func setDemand(worktreeIds: Set<UUID>) async {
        guard demandedWorktreeIds != worktreeIds else { return }
        defer { flushPerformanceSnapshot() }
        let previouslyDemandedRepoIds = demandedRepoIds()
        let previouslyDemandedBranchesByRepoId = Dictionary(
            uniqueKeysWithValues: previouslyDemandedRepoIds.map { repoId in
                (repoId, demandedBranches(repoId: repoId))
            }
        )
        demandedWorktreeIds = worktreeIds
        let currentlyDemandedRepoIds = demandedRepoIds()

        for repoId in previouslyDemandedRepoIds.subtracting(currentlyDemandedRepoIds) {
            cancelProviderRequest(repoId: repoId)
            if var state = refreshStateByRepoId[repoId] {
                state.pendingFollowUp = false
                state.pendingFollowUpRequiresRefresh = false
                state.pendingFollowUpHasUnconfirmedScopeChange = false
                state.pendingFollowUpEligibleAt = nil
                let restoredProjection = PullRequestRepositoryProjection.stable(
                    state.stablePresentation
                )
                let shouldEmitRestoredProjection = state.acceptedProjection != restoredProjection
                state.acceptedProjection = restoredProjection
                refreshStateByRepoId[repoId] = state
                if shouldEmitRestoredProjection {
                    await emitForgeEvent(
                        repoId: repoId,
                        correlationId: nil,
                        event: .pullRequestRepositoryProjectionChanged(
                            repoId: repoId,
                            projection: restoredProjection,
                            invalidatedBranches: []
                        )
                    )
                }
            }
        }
        for repoId in currentlyDemandedRepoIds {
            let currentDemandedBranches = demandedBranches(repoId: repoId)
            let previouslyDemandedBranches = previouslyDemandedBranchesByRepoId[repoId] ?? []
            let confirmedBranches: Set<String>
            if let confirmedFacts = ForgePresentationFacts.confirmedFacts(
                in: refreshStateByRepoId[repoId]?.stablePresentation ?? .unknown
            ) {
                confirmedBranches = Set(confirmedFacts.keys)
            } else {
                confirmedBranches = []
            }
            let trigger: RefreshTrigger =
                previouslyDemandedBranches != currentDemandedBranches
                    && !currentDemandedBranches.isSubset(of: confirmedBranches)
                ? .scopeChanged : .automatic
            await requestRefreshIfDemanded(repoId: repoId, trigger: trigger, correlationId: nil)
        }
        rescheduleDeadline()
    }

    package func refresh(repo repoId: UUID, correlationId: UUID? = nil) async {
        defer { flushPerformanceSnapshot() }
        await requestRefreshIfDemanded(repoId: repoId, trigger: .manual, correlationId: correlationId)
        rescheduleDeadline()
    }

    package func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        let activeSubscriptionTask = subscriptionTask
        let activeDeadlineTask = deadlineTask
        let activeProviderTasks = Array(providerTasksByRequestId.values)

        subscriptionTask?.cancel()
        deadlineTask?.cancel()
        if deadlineTask != nil {
            performanceAccumulator.recordDeadline(.cancelled)
        }
        for task in activeProviderTasks {
            performanceAccumulator.recordExecution(.cancelled)
            task.cancel()
        }
        subscriptionTask = nil
        deadlineTask = nil

        if let activeSubscriptionTask { await activeSubscriptionTask.value }
        if let activeDeadlineTask { await activeDeadlineTask.value }
        for task in activeProviderTasks { await task.value }
        providerTasksByRequestId.removeAll(keepingCapacity: false)
        providerRepoIdByRequestId.removeAll(keepingCapacity: false)

        membershipByWorktreeId.removeAll(keepingCapacity: false)
        demandedWorktreeIds.removeAll(keepingCapacity: false)
        refreshStateByRepoId.removeAll(keepingCapacity: false)
        flushPerformanceSnapshot()
    }

    private func handleIncomingRuntimeEnvelope(_ envelope: RuntimeEnvelope) async {
        guard case .worktree(let worktreeEnvelope) = envelope,
            case .gitWorkingDirectory(let gitEvent) = worktreeEnvelope.event
        else { return }
        await handleGitWorkingDirectoryEvent(
            gitEvent,
            repoId: worktreeEnvelope.repoId,
            correlationId: worktreeEnvelope.correlationId
        )
    }

    private func handleGitWorkingDirectoryEvent(
        _ event: GitWorkingDirectoryEvent,
        repoId: UUID,
        correlationId: UUID?
    ) async {
        switch event {
        case .statusOutcome:
            return
        case .snapshotChanged(let snapshot):
            await updateMembershipBranch(
                worktreeId: snapshot.worktreeId,
                repoId: snapshot.repoId,
                rootPath: snapshot.rootPath,
                branch: snapshot.branch,
                correlationId: correlationId
            )
        case .branchChanged(let worktreeId, _, _, let to):
            guard let membership = membershipByWorktreeId[worktreeId] else { return }
            await updateMembershipBranch(
                worktreeId: worktreeId,
                repoId: membership.repoId,
                rootPath: membership.rootPath,
                branch: to,
                correlationId: correlationId
            )
        case .originChanged(_, _, let to):
            await setOrigin(repo: repoId, remote: to)
        case .originUnavailable:
            await clearOrigin(repoId: repoId)
        case .worktreeDiscovered(_, let worktreePath, let branch, _):
            guard
                let matchingMembership = membershipByWorktreeId.first(where: { _, membership in
                    membership.repoId == repoId
                        && membership.rootPath == worktreePath.standardizedFileURL
                })
            else { return }
            await updateMembershipBranch(
                worktreeId: matchingMembership.key,
                repoId: repoId,
                rootPath: worktreePath,
                branch: branch,
                correlationId: correlationId
            )
        case .worktreeRemoved, .diffAvailable:
            return
        }
    }

    private func updateMembershipBranch(
        worktreeId: UUID,
        repoId: UUID,
        rootPath: URL,
        branch: String?,
        correlationId: UUID?
    ) async {
        guard let priorMembership = membershipByWorktreeId[worktreeId] else { return }
        defer { flushPerformanceSnapshot() }
        let normalizedBranch = ForgePresentationFacts.normalizedBranch(branch)
        membershipByWorktreeId[worktreeId] = WorktreeMembership(
            repoId: repoId,
            rootPath: rootPath.standardizedFileURL,
            branch: normalizedBranch
        )
        if priorMembership.repoId != repoId || priorMembership.branch != normalizedBranch {
            await invalidateBranchIfUnrepresented(
                repoId: priorMembership.repoId,
                branch: priorMembership.branch
            )
        }
        if demandedWorktreeIds.contains(worktreeId) {
            await requestRefreshIfDemanded(
                repoId: repoId,
                trigger: priorMembership.repoId != repoId || priorMembership.branch != normalizedBranch
                    ? .scopeChanged : .automatic,
                correlationId: correlationId
            )
        }
        rescheduleDeadline()
    }

    /// Confirms a repository has no resolvable git remote. This is a terminal
    /// outcome, not a mid-flight invalidation: no automatic query will ever
    /// fire again for this repo (an empty origin fails the `requestRefreshIfDemanded`
    /// origin guard), so the repo must resolve to unavailable rather than
    /// stay pending forever. Runs on both the very first time a worktree with
    /// no remote is seen (state did not exist yet) and on later loss of a
    /// previously known origin; either way the terminal fact is emitted at
    /// most once per transition into this state.
    private func clearOrigin(repoId: UUID) async {
        var state = refreshStateByRepoId[repoId] ?? RepositoryRefreshState()
        guard state.origin != nil || !state.hasEmittedUnavailable else { return }
        defer { flushPerformanceSnapshot() }
        cancelProviderRequest(repoId: repoId)
        state.generation &+= 1
        state.origin = nil
        state.lastSuccessfulRefreshAt = nil
        state.lastAttemptAt = nil
        state.backoffUntil = nil
        state.activeRequestId = nil
        state.pendingFollowUp = false
        state.pendingFollowUpRequiresRefresh = false
        state.pendingFollowUpHasUnconfirmedScopeChange = false
        state.pendingFollowUpEligibleAt = nil
        state.consecutiveFailureCount = 0
        state.consecutiveUnsuccessfulAttempts = 0
        let previousConfirmedFacts = ForgePresentationFacts.confirmedFacts(
            in: state.stablePresentation
        )
        state.stablePresentation = .unavailable(
            previousConfirmedFactsByBranch: previousConfirmedFacts
        )
        state.hasEmittedUnavailable = true
        let unavailableProjection = PullRequestRepositoryProjection.stable(
            state.stablePresentation
        )
        let shouldEmitUnavailable = state.acceptedProjection != unavailableProjection
        state.acceptedProjection = unavailableProjection
        refreshStateByRepoId[repoId] = state
        if shouldEmitUnavailable {
            await emitForgeEvent(
                repoId: repoId,
                correlationId: nil,
                event: .pullRequestRepositoryProjectionChanged(
                    repoId: repoId,
                    projection: unavailableProjection,
                    invalidatedBranches: []
                )
            )
        }
        rescheduleDeadline()
    }

    private func invalidateBranchIfUnrepresented(repoId: UUID, branch: String?) async {
        guard let branch,
            membershipByWorktreeId.values.contains(where: {
                $0.repoId == repoId && $0.branch == branch
            }) == false
        else { return }
        guard var state = refreshStateByRepoId[repoId] else {
            await emitForgeEvent(
                repoId: repoId,
                correlationId: nil,
                event: .pullRequestRepositoryProjectionChanged(
                    repoId: repoId,
                    projection: .stable(.unknown),
                    invalidatedBranches: [branch]
                )
            )
            return
        }
        let updatedStablePresentation = ForgePresentationFacts.removingConfirmedBranches(
            [branch],
            from: state.stablePresentation
        )
        state.stablePresentation = updatedStablePresentation
        let updatedProjection: PullRequestRepositoryProjection
        if let activeRequestId = state.activeRequestId {
            updatedProjection = .loading(
                baseline: updatedStablePresentation,
                requestIdentity: activeRequestId
            )
        } else {
            updatedProjection = .stable(updatedStablePresentation)
        }
        let shouldEmitProjection = state.acceptedProjection != updatedProjection
        state.acceptedProjection = updatedProjection
        refreshStateByRepoId[repoId] = state
        if shouldEmitProjection || !branch.isEmpty {
            await emitForgeEvent(
                repoId: repoId,
                correlationId: nil,
                event: .pullRequestRepositoryProjectionChanged(
                    repoId: repoId,
                    projection: updatedProjection,
                    invalidatedBranches: [branch]
                )
            )
        }
    }

    func requestRefreshIfDemanded(
        repoId: UUID,
        trigger: RefreshTrigger,
        correlationId: UUID?
    ) async {
        performanceAccumulator.recordInput(trigger.performanceInput)
        guard !isShuttingDown else {
            performanceAccumulator.recordAdmission(.noDemandRejected)
            return
        }
        let demandedBranches = demandedBranches(repoId: repoId)
        guard !demandedBranches.isEmpty else {
            performanceAccumulator.recordAdmission(.noDemandRejected)
            if var state = refreshStateByRepoId[repoId] {
                state.pendingFollowUp = false
                state.pendingFollowUpRequiresRefresh = false
                state.pendingFollowUpHasUnconfirmedScopeChange = false
                state.pendingFollowUpEligibleAt = nil
                refreshStateByRepoId[repoId] = state
            }
            return
        }
        guard var state = refreshStateByRepoId[repoId], let origin = state.origin else {
            performanceAccumulator.recordAdmission(.missingOriginRejected)
            return
        }

        if coalesceRefreshWhileProviderActive(repoId: repoId, trigger: trigger, state: &state) {
            return
        }

        let now = monotonicNow()
        if let nextEligibleAt = nextEligibleRefreshAt(state: state, bypassFreshness: trigger.bypassesFreshness),
            now < nextEligibleAt
        {
            if let backoffUntil = state.backoffUntil, backoffUntil >= nextEligibleAt {
                performanceAccumulator.recordAdmission(.backoffDeferred)
            } else {
                performanceAccumulator.recordAdmission(.freshnessDeferred)
            }
            state.pendingFollowUp = true
            state.pendingFollowUpRequiresRefresh =
                state.pendingFollowUpRequiresRefresh || trigger.requiresFollowUpRefresh
            state.pendingFollowUpHasUnconfirmedScopeChange =
                state.pendingFollowUpHasUnconfirmedScopeChange || trigger.hasUnconfirmedScopeChange
            state.pendingFollowUpEligibleAt = max(
                state.pendingFollowUpEligibleAt ?? .zero,
                nextEligibleAt
            )
            refreshStateByRepoId[repoId] = state
            return
        }

        if deferStartIfPhysicallyBlocked(repoId: repoId, trigger: trigger, now: now, state: &state) { return }

        nextProviderRequestId &+= 1
        let request = ProviderRequest(
            id: nextProviderRequestId,
            repoId: repoId,
            origin: origin,
            generation: state.generation,
            demandedBranches: demandedBranches,
            trigger: trigger,
            correlationId: correlationId
        )
        state.activeRequestId = request.id
        state.lastAttemptAt = now
        state.pendingFollowUp = false
        state.pendingFollowUpRequiresRefresh = false
        state.pendingFollowUpHasUnconfirmedScopeChange = false
        state.pendingFollowUpEligibleAt = nil
        let loadingProjection = PullRequestRepositoryProjection.loading(
            baseline: state.stablePresentation,
            requestIdentity: request.id
        )
        state.acceptedProjection = loadingProjection
        refreshStateByRepoId[repoId] = state
        performanceAccumulator.recordAdmission(.admitted)

        await emitForgeEvent(
            repoId: repoId,
            correlationId: correlationId,
            event: .pullRequestRepositoryProjectionChanged(
                repoId: repoId,
                projection: loadingProjection,
                invalidatedBranches: []
            )
        )

        guard !isShuttingDown,
            let currentState = refreshStateByRepoId[repoId],
            currentState.activeRequestId == request.id,
            currentState.generation == request.generation,
            currentState.origin == request.origin
        else { return }

        let statusProvider = self.statusProvider
        performanceAccumulator.recordExecution(.started)
        recordQueryPlan(for: request)
        providerRepoIdByRequestId[request.id] = request.repoId
        providerTasksByRequestId[request.id] = Task { [weak self, statusProvider] in
            guard let self else { return }
            let outcome = await statusProvider.pullRequests(
                origin: request.origin,
                demandedBranches: request.demandedBranches
            )
            await self.completeProviderRequest(request, outcome: outcome)
        }
        recordPhysicalPerformanceState()
        flushPerformanceSnapshot()
    }

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

    func nextEligibleRefreshAt(
        state: RepositoryRefreshState,
        bypassFreshness: Bool
    ) -> Duration? {
        var nextEligibleAt = state.backoffUntil
        if !bypassFreshness, let lastSuccessfulRefreshAt = state.lastSuccessfulRefreshAt {
            let freshnessDeadline =
                lastSuccessfulRefreshAt + AppPolicies.Forge.automaticRefreshMinimumInterval
            nextEligibleAt = max(nextEligibleAt ?? .zero, freshnessDeadline)
        }
        return nextEligibleAt
    }

    func rescheduleDeadline() {
        nextDeadlineGeneration &+= 1
        let deadlineGeneration = nextDeadlineGeneration
        if deadlineTask != nil {
            performanceAccumulator.recordDeadline(.cancelled)
            performanceAccumulator.recordDeadline(.rescheduled)
        }
        deadlineTask?.cancel()
        deadlineTask = nil
        guard !isShuttingDown else { return }

        let now = monotonicNow()
        let deadlines = deadlineCandidates()
        guard let earliestDeadline = deadlines.min() else { return }
        let waitDuration = max(.zero, earliestDeadline - now)
        let delay = self.delay
        performanceAccumulator.recordDeadline(.scheduled)
        deadlineTask = Task { [weak self, delay] in
            do {
                try await delay.wait(waitDuration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.deadlineDidFire(generation: deadlineGeneration)
        }
    }

    private func deadlineDidFire(generation: UInt64) async {
        guard generation == nextDeadlineGeneration else { return }
        performanceAccumulator.recordDeadline(.fired)
        deadlineTask = nil
        let repoIds = demandedRepoIds()
        for repoId in repoIds {
            let trigger =
                refreshStateByRepoId[repoId].map { state in
                    state.pendingFollowUp ? pendingFollowUpTrigger(for: state) : .automatic
                } ?? .automatic
            await requestRefreshIfDemanded(repoId: repoId, trigger: trigger, correlationId: nil)
        }
        rescheduleDeadline()
        flushPerformanceSnapshot()
    }

    private func cancelProviderRequest(repoId: UUID) {
        if let activeRequestId = refreshStateByRepoId[repoId]?.activeRequestId,
            let providerTask = providerTasksByRequestId[activeRequestId]
        {
            performanceAccumulator.recordExecution(.cancelled)
            providerTask.cancel()
        }
        if var state = refreshStateByRepoId[repoId] {
            state.activeRequestId = nil
            state.pendingFollowUp = false
            state.pendingFollowUpRequiresRefresh = false
            state.pendingFollowUpHasUnconfirmedScopeChange = false
            state.pendingFollowUpEligibleAt = nil
            refreshStateByRepoId[repoId] = state
        }
    }

    func demandedRepoIds() -> Set<UUID> {
        Set(demandedWorktreeIds.compactMap { membershipByWorktreeId[$0]?.repoId })
    }

    func demandedBranches(repoId: UUID) -> Set<String> {
        Set(
            demandedWorktreeIds.compactMap { worktreeId in
                guard let membership = membershipByWorktreeId[worktreeId],
                    membership.repoId == repoId
                else { return nil }
                return membership.branch
            }
        )
    }

    func representedBranches(repoId: UUID) -> Set<String> {
        Set(
            membershipByWorktreeId.values.compactMap { membership in
                guard membership.repoId == repoId else { return nil }
                return membership.branch
            }
        )
    }

    private func emitForgeEvent(
        repoId: UUID,
        correlationId: UUID?,
        event: ForgeEvent
    ) async {
        if case .pullRequestRepositoryProjectionChanged(_, _, let invalidatedBranches) = event {
            performanceAccumulator.recordPublication(.published)
            if !invalidatedBranches.isEmpty {
                performanceAccumulator.recordPublication(.invalidated)
            }
        }
        nextEnvelopeSequence &+= 1
        let envelopeSequence = nextEnvelopeSequence
        let runtimeEnvelope = RuntimeEnvelope.worktree(
            WorktreeEnvelope(
                source: .system(.service(.gitForge(provider: providerName))),
                seq: envelopeSequence,
                timestamp: envelopeClock.now,
                correlationId: correlationId,
                repoId: repoId,
                worktreeId: nil,
                event: .forge(event)
            )
        )

        await beforeEventEmission?(event)
        let droppedCount = (await runtimeBus.post(runtimeEnvelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Forge event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(envelopeSequence, privacy: .public)"
            )
        }
    }
}

extension ForgeActor {
    private func completeProviderRequest(
        _ request: ProviderRequest,
        outcome: ForgePullRequestQueryOutcome
    ) async {
        defer { flushPerformanceSnapshot() }
        providerTasksByRequestId.removeValue(forKey: request.id)
        providerRepoIdByRequestId.removeValue(forKey: request.id)
        recordPhysicalPerformanceState()
        guard !isShuttingDown else { return }
        performanceAccumulator.recordExecution(.completed)
        guard var state = refreshStateByRepoId[request.repoId] else {
            performanceAccumulator.recordExecution(.superseded)
            performanceAccumulator.recordValidation(.staleGeneration)
            await rearmAfterProviderPhysicalCompletion()
            return
        }
        guard state.generation == request.generation else {
            performanceAccumulator.recordExecution(.superseded)
            performanceAccumulator.recordValidation(.staleGeneration)
            await rearmAfterProviderPhysicalCompletion()
            return
        }
        guard state.origin == request.origin else {
            performanceAccumulator.recordExecution(.superseded)
            performanceAccumulator.recordValidation(.staleOrigin)
            await rearmAfterProviderPhysicalCompletion()
            return
        }
        guard state.activeRequestId == request.id else {
            performanceAccumulator.recordExecution(.superseded)
            await rearmAfterProviderPhysicalCompletion()
            return
        }

        state.activeRequestId = nil
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
