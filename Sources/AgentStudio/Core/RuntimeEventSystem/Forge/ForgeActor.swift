import AgentStudioInfrastructure
import Foundation
import os

package actor ForgeActor {
    private struct WorktreeMembership: Sendable {
        let repoId: UUID
        let rootPath: URL
        var branch: String?
    }

    private struct RepositoryRefreshState {
        var origin: String?
        var generation: UInt64 = 0
        var lastSuccessfulRefreshAt: Duration?
        var lastAttemptAt: Duration?
        var backoffUntil: Duration?
        var activeRequestId: UInt64?
        var pendingFollowUp = false
    }

    private struct ProviderRequest: Sendable {
        let id: UInt64
        let repoId: UUID
        let origin: String
        let generation: UInt64
        let demandedBranches: Set<String>
        let correlationId: UUID?
    }

    private enum RefreshTrigger {
        case automatic
        case manual
        case followUp

        var bypassesFreshness: Bool {
            switch self {
            case .automatic: false
            case .manual, .followUp: true
            }
        }
    }

    private static let logger = Logger(subsystem: "com.agentstudio", category: "ForgeActor")

    private let runtimeBus: EventBus<RuntimeEnvelope>
    private let statusProvider: any ForgeStatusProvider
    private let providerName: String
    private let envelopeClock: ContinuousClock
    private let monotonicNow: @Sendable () -> Duration
    private let delay: AsyncDelay
    private let subscriptionBufferLimit: Int

    private var subscriptionTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var providerTasksByRepoId: [UUID: Task<Void, Never>] = [:]
    private var nextDeadlineGeneration: UInt64 = 0
    private var nextProviderRequestId: UInt64 = 0
    private var nextEnvelopeSequence: UInt64 = 0
    private var membershipByWorktreeId: [UUID: WorktreeMembership] = [:]
    private var demandedWorktreeIds: Set<UUID> = []
    private var refreshStateByRepoId: [UUID: RepositoryRefreshState] = [:]
    private var isShuttingDown = false

    package init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        statusProvider: any ForgeStatusProvider,
        providerName: String = "github",
        envelopeClock: ContinuousClock = ContinuousClock(),
        monotonicNow: @escaping @Sendable () -> Duration = {
            .seconds(ProcessInfo.processInfo.systemUptime)
        },
        sleepClock: (any Clock<Duration> & Sendable)? = nil,
        subscriptionBufferLimit: Int = 256
    ) {
        runtimeBus = bus
        self.statusProvider = statusProvider
        self.providerName = providerName
        self.envelopeClock = envelopeClock
        self.monotonicNow = monotonicNow
        delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep
        self.subscriptionBufferLimit = subscriptionBufferLimit
    }

    isolated deinit {
        subscriptionTask?.cancel()
        deadlineTask?.cancel()
        for task in providerTasksByRepoId.values {
            task.cancel()
        }
    }

    package func start() async {
        guard subscriptionTask == nil else { return }
        let stream = await runtimeBus.subscribe(
            policy: .lossyNewest(subscriptionBufferLimit),
            subscriberName: "ForgeActor"
        )
        subscriptionTask = Task { [weak self] in
            for await runtimeEnvelope in stream {
                guard !Task.isCancelled, let self else { return }
                await self.handleIncomingRuntimeEnvelope(runtimeEnvelope)
            }
        }
    }

    package func register(
        worktreeId: UUID,
        repoId: UUID,
        rootPath: URL,
        branch: String? = nil
    ) async {
        let normalizedBranch = Self.normalizedBranch(branch)
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
        requestRefreshIfDemanded(repoId: repoId, trigger: .automatic, correlationId: nil)
        rescheduleDeadline()
    }

    package func unregister(worktreeId: UUID) async {
        guard let removedMembership = membershipByWorktreeId.removeValue(forKey: worktreeId) else { return }
        demandedWorktreeIds.remove(worktreeId)
        await invalidateBranchIfUnrepresented(
            repoId: removedMembership.repoId,
            branch: removedMembership.branch
        )
        requestRefreshIfDemanded(
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
        let replacedExistingOrigin = state.origin != nil

        cancelProviderRequest(repoId: repoId)
        state.generation &+= 1
        state.origin = normalizedOrigin
        state.lastSuccessfulRefreshAt = nil
        state.lastAttemptAt = nil
        state.backoffUntil = nil
        state.activeRequestId = nil
        state.pendingFollowUp = false
        refreshStateByRepoId[repoId] = state

        if replacedExistingOrigin {
            await emitForgeEvent(
                repoId: repoId,
                correlationId: nil,
                event: .pullRequestRepositoryInvalidated(repoId: repoId)
            )
        }
        requestRefreshIfDemanded(repoId: repoId, trigger: .automatic, correlationId: nil)
        rescheduleDeadline()
    }

    package func removeRepository(repo repoId: UUID) async {
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
            event: .pullRequestRepositoryInvalidated(repoId: repoId)
        )
        rescheduleDeadline()
    }

    package func setDemand(worktreeIds: Set<UUID>) async {
        guard demandedWorktreeIds != worktreeIds else { return }
        let previouslyDemandedRepoIds = demandedRepoIds()
        demandedWorktreeIds = worktreeIds
        let currentlyDemandedRepoIds = demandedRepoIds()

        for repoId in previouslyDemandedRepoIds.subtracting(currentlyDemandedRepoIds) {
            if var state = refreshStateByRepoId[repoId] {
                state.pendingFollowUp = false
                refreshStateByRepoId[repoId] = state
            }
        }
        for repoId in currentlyDemandedRepoIds {
            requestRefreshIfDemanded(repoId: repoId, trigger: .automatic, correlationId: nil)
        }
        rescheduleDeadline()
    }

    package func refresh(repo repoId: UUID, correlationId: UUID? = nil) async {
        requestRefreshIfDemanded(repoId: repoId, trigger: .manual, correlationId: correlationId)
        rescheduleDeadline()
    }

    package func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        let activeSubscriptionTask = subscriptionTask
        let activeDeadlineTask = deadlineTask
        let activeProviderTasks = Array(providerTasksByRepoId.values)

        subscriptionTask?.cancel()
        deadlineTask?.cancel()
        for task in activeProviderTasks {
            task.cancel()
        }
        subscriptionTask = nil
        deadlineTask = nil
        providerTasksByRepoId.removeAll(keepingCapacity: false)

        if let activeSubscriptionTask { await activeSubscriptionTask.value }
        if let activeDeadlineTask { await activeDeadlineTask.value }
        for task in activeProviderTasks { await task.value }

        deadlineTask?.cancel()
        for task in providerTasksByRepoId.values {
            task.cancel()
        }
        deadlineTask = nil
        providerTasksByRepoId.removeAll(keepingCapacity: false)
        membershipByWorktreeId.removeAll(keepingCapacity: false)
        demandedWorktreeIds.removeAll(keepingCapacity: false)
        refreshStateByRepoId.removeAll(keepingCapacity: false)
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
        let normalizedBranch = Self.normalizedBranch(branch)
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
            requestRefreshIfDemanded(
                repoId: repoId,
                trigger: .automatic,
                correlationId: correlationId
            )
        }
        rescheduleDeadline()
    }

    private func clearOrigin(repoId: UUID) async {
        guard var state = refreshStateByRepoId[repoId], state.origin != nil else { return }
        cancelProviderRequest(repoId: repoId)
        state.generation &+= 1
        state.origin = nil
        state.lastSuccessfulRefreshAt = nil
        state.lastAttemptAt = nil
        state.backoffUntil = nil
        state.activeRequestId = nil
        state.pendingFollowUp = false
        refreshStateByRepoId[repoId] = state
        await emitForgeEvent(
            repoId: repoId,
            correlationId: nil,
            event: .pullRequestRepositoryInvalidated(repoId: repoId)
        )
        rescheduleDeadline()
    }

    private func invalidateBranchIfUnrepresented(repoId: UUID, branch: String?) async {
        guard let branch,
            membershipByWorktreeId.values.contains(where: {
                $0.repoId == repoId && $0.branch == branch
            }) == false
        else { return }
        await emitForgeEvent(
            repoId: repoId,
            correlationId: nil,
            event: .pullRequestBranchesInvalidated(repoId: repoId, branches: [branch])
        )
    }

    private func requestRefreshIfDemanded(
        repoId: UUID,
        trigger: RefreshTrigger,
        correlationId: UUID?
    ) {
        guard !isShuttingDown else { return }
        let demandedBranches = demandedBranches(repoId: repoId)
        guard !demandedBranches.isEmpty else {
            if var state = refreshStateByRepoId[repoId] {
                state.pendingFollowUp = false
                refreshStateByRepoId[repoId] = state
            }
            return
        }
        guard var state = refreshStateByRepoId[repoId], let origin = state.origin else { return }

        if state.activeRequestId != nil {
            state.pendingFollowUp = true
            refreshStateByRepoId[repoId] = state
            return
        }

        let now = monotonicNow()
        if let nextEligibleAt = nextEligibleRefreshAt(state: state, bypassFreshness: trigger.bypassesFreshness),
            now < nextEligibleAt
        {
            state.pendingFollowUp = true
            refreshStateByRepoId[repoId] = state
            return
        }

        nextProviderRequestId &+= 1
        let request = ProviderRequest(
            id: nextProviderRequestId,
            repoId: repoId,
            origin: origin,
            generation: state.generation,
            demandedBranches: demandedBranches,
            correlationId: correlationId
        )
        state.activeRequestId = request.id
        state.lastAttemptAt = now
        state.pendingFollowUp = false
        refreshStateByRepoId[repoId] = state

        let statusProvider = self.statusProvider
        providerTasksByRepoId[repoId] = Task { [weak self, statusProvider] in
            let outcome = await statusProvider.pullRequests(origin: request.origin)
            guard let self else { return }
            await self.completeProviderRequest(request, outcome: outcome)
        }
    }

    private func completeProviderRequest(
        _ request: ProviderRequest,
        outcome: ForgePullRequestQueryOutcome
    ) async {
        guard !isShuttingDown else {
            providerTasksByRepoId.removeValue(forKey: request.repoId)
            return
        }
        guard var state = refreshStateByRepoId[request.repoId],
            state.activeRequestId == request.id,
            state.generation == request.generation,
            state.origin == request.origin
        else { return }

        providerTasksByRepoId.removeValue(forKey: request.repoId)
        state.activeRequestId = nil
        let completionTime = monotonicNow()
        let event: ForgeEvent

        switch outcome {
        case .complete(let pullRequests):
            state.lastSuccessfulRefreshAt = completionTime
            state.backoffUntil = nil
            let stillRepresentedRequestedBranches = request.demandedBranches.intersection(
                representedBranches(repoId: request.repoId)
            )
            event = .pullRequestsChanged(
                repoId: request.repoId,
                factsByBranch: ForgePullRequestFactsProjector.project(
                    pullRequests: pullRequests,
                    demandedBranches: stillRepresentedRequestedBranches
                )
            )
        case .truncated:
            state.backoffUntil = minimumRetryAt(state: state, completionTime: completionTime)
            event = .refreshFailed(
                repoId: request.repoId,
                error: "GitHub pull request result reached the 200-item cap"
            )
        case .rateLimited(let retryAfterSeconds):
            let retryAfterDeadline = retryAfterSeconds.map {
                completionTime + .seconds(Int64($0))
            }
            state.backoffUntil = max(
                minimumRetryAt(state: state, completionTime: completionTime),
                retryAfterDeadline ?? .zero
            )
            event = .rateLimited(repoId: request.repoId, retryAfterSeconds: retryAfterSeconds)
        case .failed(let message):
            state.backoffUntil = minimumRetryAt(state: state, completionTime: completionTime)
            event = .refreshFailed(repoId: request.repoId, error: message)
        }

        refreshStateByRepoId[request.repoId] = state
        await emitForgeEvent(
            repoId: request.repoId,
            correlationId: request.correlationId,
            event: event
        )

        guard var currentState = refreshStateByRepoId[request.repoId],
            currentState.generation == request.generation,
            currentState.activeRequestId == nil
        else { return }
        if currentState.pendingFollowUp {
            currentState.pendingFollowUp = false
            refreshStateByRepoId[request.repoId] = currentState
            requestRefreshIfDemanded(
                repoId: request.repoId,
                trigger: .followUp,
                correlationId: nil
            )
        }
        rescheduleDeadline()
    }

    private func minimumRetryAt(
        state: RepositoryRefreshState,
        completionTime: Duration
    ) -> Duration {
        (state.lastAttemptAt ?? completionTime) + AppPolicies.Forge.automaticRefreshMinimumInterval
    }

    private func nextEligibleRefreshAt(
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

    private func rescheduleDeadline() {
        nextDeadlineGeneration &+= 1
        let deadlineGeneration = nextDeadlineGeneration
        deadlineTask?.cancel()
        deadlineTask = nil
        guard !isShuttingDown else { return }

        let now = monotonicNow()
        let deadlines = demandedRepoIds().compactMap { repoId -> Duration? in
            guard let state = refreshStateByRepoId[repoId],
                state.origin != nil,
                state.activeRequestId == nil
            else { return nil }
            return nextEligibleRefreshAt(state: state, bypassFreshness: false)
        }
        guard let earliestDeadline = deadlines.min() else { return }
        let waitDuration = max(.zero, earliestDeadline - now)
        let delay = self.delay
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

    private func deadlineDidFire(generation: UInt64) {
        guard generation == nextDeadlineGeneration else { return }
        deadlineTask = nil
        let repoIds = demandedRepoIds()
        for repoId in repoIds {
            requestRefreshIfDemanded(repoId: repoId, trigger: .automatic, correlationId: nil)
        }
        rescheduleDeadline()
    }

    private func cancelProviderRequest(repoId: UUID) {
        providerTasksByRepoId.removeValue(forKey: repoId)?.cancel()
        if var state = refreshStateByRepoId[repoId] {
            state.activeRequestId = nil
            state.pendingFollowUp = false
            refreshStateByRepoId[repoId] = state
        }
    }

    private func demandedRepoIds() -> Set<UUID> {
        Set(demandedWorktreeIds.compactMap { membershipByWorktreeId[$0]?.repoId })
    }

    private func demandedBranches(repoId: UUID) -> Set<String> {
        Set(
            demandedWorktreeIds.compactMap { worktreeId in
                guard let membership = membershipByWorktreeId[worktreeId],
                    membership.repoId == repoId
                else { return nil }
                return membership.branch
            }
        )
    }

    private func representedBranches(repoId: UUID) -> Set<String> {
        Set(
            membershipByWorktreeId.values.compactMap { membership in
                guard membership.repoId == repoId else { return nil }
                return membership.branch
            }
        )
    }

    private static func normalizedBranch(_ branch: String?) -> String? {
        guard let branch, !branch.isEmpty else { return nil }
        return branch
    }

    private func emitForgeEvent(
        repoId: UUID,
        correlationId: UUID?,
        event: ForgeEvent
    ) async {
        nextEnvelopeSequence &+= 1
        let runtimeEnvelope = RuntimeEnvelope.worktree(
            WorktreeEnvelope(
                source: .system(.service(.gitForge(provider: providerName))),
                seq: nextEnvelopeSequence,
                timestamp: envelopeClock.now,
                correlationId: correlationId,
                repoId: repoId,
                worktreeId: nil,
                event: .forge(event)
            )
        )

        let droppedCount = (await runtimeBus.post(runtimeEnvelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Forge event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(self.nextEnvelopeSequence, privacy: .public)"
            )
        }
    }
}
