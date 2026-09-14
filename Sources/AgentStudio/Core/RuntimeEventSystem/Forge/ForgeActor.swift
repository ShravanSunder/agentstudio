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
    private let providerRequestDidReturn: (@Sendable (UInt64) -> Void)?

    private var subscriptionTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    var providerTasksByRequestId: [UInt64: Task<Void, Never>] = [:]
    var providerRepoIdByRequestId: [UInt64: UUID] = [:]
    private var nextDeadlineGeneration: UInt64 = 0
    var hasBoundObservationLifetimes = false
    var observationLifetimesByWorktreeID: [UUID: WorktreeObservationLifetime] = [:]
    var observationLifetimesByRepositoryID: [UUID: RepositoryObservationLifetime] = [:]
    private var nextProviderRequestId: UInt64 = 0
    private var nextEnvelopeSequence: UInt64 = 0
    private var membershipByWorktreeId: [UUID: WorktreeMembership] = [:]
    private var demandedWorktreeIds: Set<UUID> = []
    var refreshStateByRepoId: [UUID: RepositoryRefreshState] = [:]
    var explicitUpdateAttemptsById: [UUID: ExplicitRepositoryUpdateAttempt] = [:]
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
        beforeEventEmission: (@Sendable (ForgeEvent) async -> Void)? = nil,
        providerRequestDidReturn: (@Sendable (UInt64) -> Void)? = nil
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
        self.providerRequestDidReturn = providerRequestDidReturn
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
        refreshExplicitUpdateScopes(repoId: repoId)
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
        refreshExplicitUpdateScopes(repoId: removedMembership.repoId)
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
        settleExplicitUpdateAttemptsAfterLogicalInvalidation(repoId: repoId)
        state.generation &+= 1
        state.origin = normalizedOrigin
        state.lastSuccessfulRefreshAt = nil
        state.lastAttemptAt = nil
        state.backoffUntil = nil
        state.activeRequestId = nil
        state.activeRequestSignature = nil
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

    @discardableResult
    package func removeRepository(repo repoId: UUID, expectedLifetime: RepositoryObservationLifetime? = nil) async
        -> Bool
    {
        if let current = observationLifetimesByRepositoryID[repoId], current != expectedLifetime { return false }
        defer { flushPerformanceSnapshot() }
        cancelProviderRequest(repoId: repoId)
        settleExplicitUpdateAttemptsAfterLogicalInvalidation(repoId: repoId)
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
        return true
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
            if !hasExplicitUpdateInterest(repoId: repoId) {
                cancelProviderRequest(repoId: repoId)
            }
            if var state = refreshStateByRepoId[repoId] {
                if !hasExplicitUpdateInterest(repoId: repoId) {
                    state.pendingFollowUp = false
                    state.pendingFollowUpRequiresRefresh = false
                    state.pendingFollowUpHasUnconfirmedScopeChange = false
                    state.pendingFollowUpEligibleAt = nil
                }
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
        settleAllExplicitUpdateAttempts(.cancelled)
        flushPerformanceSnapshot()
    }

    private func handleIncomingRuntimeEnvelope(_ envelope: RuntimeEnvelope) async {
        guard case .worktree(let worktreeEnvelope) = envelope,
            case .gitWorkingDirectory(let gitEvent) = worktreeEnvelope.event
        else { return }
        if hasBoundObservationLifetimes {
            guard let worktreeID = worktreeEnvelope.worktreeId,
                case .worktree(let lifetime) = worktreeEnvelope.observationLifetime,
                observationLifetimesByWorktreeID[worktreeID] == lifetime
            else { return }
        }
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

    package func appliedAutomaticDemandWorktreeIds() -> Set<UUID> {
        demandedWorktreeIds
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
        refreshExplicitUpdateScopes(repoId: repoId)
        if priorMembership.repoId != repoId || priorMembership.branch != normalizedBranch {
            await invalidateBranchIfUnrepresented(
                repoId: priorMembership.repoId,
                branch: priorMembership.branch
            )
        }
        if demandedWorktreeIds.contains(worktreeId) || hasExplicitUpdateInterest(repoId: repoId) {
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
        settleExplicitUpdateAttemptsAfterLogicalInvalidation(repoId: repoId)
        state.generation &+= 1
        state.origin = nil
        state.lastSuccessfulRefreshAt = nil
        state.lastAttemptAt = nil
        state.backoffUntil = nil
        state.activeRequestId = nil
        state.activeRequestSignature = nil
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
}

extension ForgeActor {
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
        let demandedBranches = repositoryFactRefreshBranches(repoId: repoId)
        guard !demandedBranches.isEmpty else {
            performanceAccumulator.recordAdmission(.noDemandRejected)
            if var state = refreshStateByRepoId[repoId], !hasExplicitUpdateInterest(repoId: repoId) {
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
            correlationId: correlationId,
            explicitAttemptIds: explicitAttemptIds(repoId: repoId),
            observationLifetime: observationLifetimesByRepositoryID[repoId]
        )
        state.activeRequestId = request.id
        state.activeRequestSignature = request.signature
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

        startProviderRequest(request)
    }

    private func startProviderRequest(_ request: ProviderRequest) {
        let statusProvider = self.statusProvider
        recordProviderStartPerformance(for: request)
        providerRepoIdByRequestId[request.id] = request.repoId
        providerTasksByRequestId[request.id] = Task { [weak self, statusProvider] in
            defer { self?.providerRequestDidReturn?(request.id) }
            guard let self else { return }
            let outcome = await statusProvider.pullRequests(
                origin: request.origin,
                demandedBranches: request.demandedBranches
            )
            await RepositoryObservationRequestContext.$repository.withValue(request.observationLifetime) {
                await self.completeProviderRequest(request, outcome: outcome)
            }
        }
        recordPhysicalPerformanceState()
        flushPerformanceSnapshot()
    }

    private func recordProviderStartPerformance(for request: ProviderRequest) {
        if !demandedRepoIds().contains(request.repoId), request.explicitAttemptIds.isEmpty {
            performanceAccumulator.recordAutomaticWithoutDemandStart()
        }
        performanceAccumulator.recordExecution(.started)
        recordQueryPlan(for: request)
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
        let now = monotonicNow()
        if consumeCapacityFallbacksDue(at: now) {
            rescheduleDeadline()
            flushPerformanceSnapshot()
            return
        }
        let repoIds = repositoryFactRefreshRepoIds()
            .filter { deadlineCandidate(repoId: $0).map { $0 <= now } == true }
            .sorted { $0.uuidString < $1.uuidString }
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

    func cancelProviderRequest(repoId: UUID) {
        if let activeRequestId = refreshStateByRepoId[repoId]?.activeRequestId,
            let providerTask = providerTasksByRequestId[activeRequestId]
        {
            performanceAccumulator.recordExecution(.cancelled)
            providerTask.cancel()
        }
        if var state = refreshStateByRepoId[repoId] {
            state.activeRequestId = nil
            state.activeRequestSignature = nil
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

    func repositoryFactRefreshBranches(repoId: UUID) -> Set<String> {
        demandedBranches(repoId: repoId).union(
            explicitUpdateAttemptsById.values
                .filter { $0.repoId == repoId }
                .reduce(into: Set<String>()) { branches, attempt in
                    branches.formUnion(attempt.branches)
                }
        )
    }

    func refreshExplicitUpdateScopes(repoId: UUID) {
        let currentBranches = representedBranches(repoId: repoId)
        guard !currentBranches.isEmpty else { return }
        for attemptId in explicitUpdateAttemptsById.keys {
            guard var attempt = explicitUpdateAttemptsById[attemptId], attempt.repoId == repoId,
                attempt.branches != currentBranches
            else { continue }
            attempt.branches = currentBranches
            explicitUpdateAttemptsById[attemptId] = attempt
            if var state = refreshStateByRepoId[repoId] {
                state.pendingFollowUp = true
                state.pendingFollowUpHasUnconfirmedScopeChange = true
                state.pendingFollowUpEligibleAt = nil
                refreshStateByRepoId[repoId] = state
            }
        }
    }

    func representedBranches(repoId: UUID) -> Set<String> {
        Set(
            membershipByWorktreeId.values.compactMap { membership in
                guard membership.repoId == repoId else { return nil }
                return membership.branch
            }
        )
    }

    func emitForgeEvent(
        repoId: UUID,
        correlationId: UUID?,
        event: ForgeEvent
    ) async {
        let capturedLifetime =
            RepositoryObservationRequestContext.repository ?? observationLifetimesByRepositoryID[repoId]
        guard capturedLifetime == observationLifetimesByRepositoryID[repoId] else { return }
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
                event: .forge(event),
                observationLifetime: capturedLifetime.map(RepositoryFactObservationLifetime.repository) ?? .unscoped
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
