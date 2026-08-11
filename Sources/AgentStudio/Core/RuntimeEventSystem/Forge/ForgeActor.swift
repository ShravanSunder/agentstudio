import AgentStudioInfrastructure
import Foundation
import os

package protocol ForgeStatusProvider: Sendable {
    func pullRequestCounts(origin: String, branches: Set<String>) async throws -> [String: Int]
}

enum ForgeStatusProviderError: Error, Sendable {
    case unsupportedRemote(String)
    case commandFailed(message: String)
    case invalidResponse(String)
}

package struct GitHubCLIForgeStatusProvider: ForgeStatusProvider {
    private struct PullRequestHead: Decodable {
        let headRefName: String
    }

    private let processExecutor: any ProcessExecutor

    package init(processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 8)) {
        self.processExecutor = processExecutor
    }

    package func pullRequestCounts(origin: String, branches: Set<String>) async throws -> [String: Int] {
        let trackedBranches = Set(branches.filter { !$0.isEmpty })
        guard !trackedBranches.isEmpty else { return [:] }

        guard let repoSlug = RemoteIdentityNormalizer.extractSlug(origin) else {
            throw ForgeStatusProviderError.unsupportedRemote(origin)
        }

        let result = try await processExecutor.execute(
            command: "gh",
            args: [
                "pr",
                "list",
                "--repo", repoSlug,
                "--state", "open",
                "--json", "headRefName",
                "--limit", "200",
            ],
            cwd: nil,
            environment: nil
        )

        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ForgeStatusProviderError.commandFailed(message: message)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw ForgeStatusProviderError.invalidResponse("gh output is not valid UTF-8")
        }
        let pullRequests = try JSONDecoder().decode([PullRequestHead].self, from: data)
        var counts = Dictionary(uniqueKeysWithValues: trackedBranches.map { ($0, 0) })
        for pullRequest in pullRequests {
            guard trackedBranches.contains(pullRequest.headRefName) else { continue }
            counts[pullRequest.headRefName, default: 0] += 1
        }
        return counts
    }
}

package actor ForgeActor {
    private struct RepoRefreshState {
        var generation: UInt64 = 0
        var inFlightTask: Task<Void, Never>?
        var backoffTask: Task<Void, Never>?
        var hasPendingRefresh = false
        var pendingCorrelationId: UUID?
        var consecutiveFailureCount = 0
        var lastPublishedCountsByBranch: [String: Int]?
    }

    private enum RefreshResult: Sendable {
        case success([String: Int])
        case failure(String)
    }

    private static let logger = Logger(subsystem: "com.agentstudio", category: "ForgeActor")

    private let runtimeBus: EventBus<RuntimeEnvelope>
    private let statusProvider: any ForgeStatusProvider
    private let providerName: String
    private let envelopeClock: ContinuousClock
    private let pollInterval: Duration
    private let delay: AsyncDelay
    private let subscriptionBufferLimit: Int

    private var subscriptionTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var nextEnvelopeSequence: UInt64 = 0
    private var repoOriginByRepoId: [UUID: String] = [:]
    private var branchesByRepoId: [UUID: Set<String>] = [:]
    private var refreshStateByRepoId: [UUID: RepoRefreshState] = [:]

    package init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        statusProvider: any ForgeStatusProvider,
        providerName: String = "github",
        envelopeClock: ContinuousClock = ContinuousClock(),
        pollInterval: Duration = AppPolicies.ForgeRefresh.defaultPollingInterval,
        sleepClock: (any Clock<Duration> & Sendable)? = nil,
        subscriptionBufferLimit: Int = 256
    ) {
        self.runtimeBus = bus
        self.statusProvider = statusProvider
        self.providerName = providerName
        self.envelopeClock = envelopeClock
        self.pollInterval = pollInterval
        delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep
        self.subscriptionBufferLimit = subscriptionBufferLimit
    }

    isolated deinit {
        subscriptionTask?.cancel()
        pollingTask?.cancel()
        for refreshState in refreshStateByRepoId.values {
            refreshState.inFlightTask?.cancel()
            refreshState.backoffTask?.cancel()
        }
    }

    package func start() async {
        if subscriptionTask == nil {
            let stream = await runtimeBus.subscribe(
                policy: .lossyNewest(subscriptionBufferLimit),
                subscriberName: "ForgeActor",
                factInterest: .matching([.worktreeGitWorkingDirectory])
            )
            subscriptionTask = Task { [weak self] in
                for await runtimeEnvelope in stream {
                    guard !Task.isCancelled else { break }
                    guard let self else { return }
                    await self.handleIncomingRuntimeEnvelope(runtimeEnvelope)
                }
            }
        }

        if pollingTask == nil {
            let delay = self.delay
            let pollInterval = self.pollInterval
            pollingTask = Task { [weak self, delay, pollInterval] in
                while !Task.isCancelled {
                    do {
                        try await delay.wait(pollInterval)
                    } catch is CancellationError {
                        return
                    } catch {
                        Self.logger.warning(
                            "Unexpected forge polling sleep failure: \(String(describing: error), privacy: .public)"
                        )
                        continue
                    }

                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    await self.refreshTrackedRepos()
                }
            }
        }
    }

    package func register(repo repoId: UUID, remote: String) async {
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty else {
            await unregister(repo: repoId)
            return
        }

        repoOriginByRepoId[repoId] = trimmedRemote
        if branchesByRepoId[repoId] == nil {
            branchesByRepoId[repoId] = []
        }
        requestRefresh(repoId: repoId, correlationId: nil)
    }

    package func unregister(repo repoId: UUID) async {
        repoOriginByRepoId.removeValue(forKey: repoId)
        branchesByRepoId.removeValue(forKey: repoId)
        let refreshState = refreshStateByRepoId.removeValue(forKey: repoId)
        refreshState?.inFlightTask?.cancel()
        refreshState?.backoffTask?.cancel()
    }

    package func refresh(repo repoId: UUID, correlationId: UUID? = nil) async {
        requestRefresh(repoId: repoId, correlationId: correlationId)
    }

    package func shutdown() async {
        let activeSubscription = subscriptionTask
        let activePolling = pollingTask

        subscriptionTask?.cancel()
        pollingTask?.cancel()
        subscriptionTask = nil
        pollingTask = nil

        if let activeSubscription {
            await activeSubscription.value
        }
        if let activePolling {
            await activePolling.value
        }

        for refreshState in refreshStateByRepoId.values {
            refreshState.inFlightTask?.cancel()
            refreshState.backoffTask?.cancel()
        }

        repoOriginByRepoId.removeAll(keepingCapacity: false)
        branchesByRepoId.removeAll(keepingCapacity: false)
        refreshStateByRepoId.removeAll(keepingCapacity: false)
    }

    private func handleIncomingRuntimeEnvelope(_ envelope: RuntimeEnvelope) async {
        switch envelope {
        case .worktree(let worktreeEnvelope):
            guard case .gitWorkingDirectory(let gitEvent) = worktreeEnvelope.event else { return }
            await handleGitWorkingDirectoryEvent(
                gitEvent,
                repoId: worktreeEnvelope.repoId,
                correlationId: worktreeEnvelope.correlationId
            )
        case .system, .pane:
            return
        }
    }

    private func handleGitWorkingDirectoryEvent(
        _ event: GitWorkingDirectoryEvent,
        repoId: UUID,
        correlationId: UUID?
    ) async {
        switch event {
        case .snapshotChanged(let snapshot):
            if let branch = snapshot.branch, !branch.isEmpty {
                branchesByRepoId[repoId, default: []].insert(branch)
            }
        case .branchChanged(_, _, _, let to):
            if !to.isEmpty {
                branchesByRepoId[repoId, default: []].insert(to)
            }
            await refresh(repo: repoId, correlationId: correlationId)
        case .originChanged(_, _, let to):
            await register(repo: repoId, remote: to)
        case .originUnavailable:
            return
        case .worktreeDiscovered(_, _, let branch, _):
            if !branch.isEmpty {
                branchesByRepoId[repoId, default: []].insert(branch)
            }
        case .worktreeRemoved, .diffAvailable:
            return
        }
    }

    private func refreshTrackedRepos() async {
        guard !Task.isCancelled else { return }
        let repoIds = Array(repoOriginByRepoId.keys)
        for repoId in repoIds {
            requestRefresh(repoId: repoId, correlationId: nil)
        }
    }

    private func requestRefresh(repoId: UUID, correlationId: UUID?) {
        guard !Task.isCancelled else { return }
        guard let origin = repoOriginByRepoId[repoId], !origin.isEmpty else { return }
        var refreshState = refreshStateByRepoId[repoId] ?? RepoRefreshState()
        guard refreshState.inFlightTask == nil, refreshState.backoffTask == nil else {
            refreshState.hasPendingRefresh = true
            refreshState.pendingCorrelationId = correlationId
            refreshStateByRepoId[repoId] = refreshState
            return
        }

        refreshState.generation += 1
        let generation = refreshState.generation
        let trackedBranches = branchesByRepoId[repoId] ?? []
        let statusProvider = self.statusProvider
        let refreshTask = Task { [weak self, statusProvider] in
            let result: RefreshResult
            do {
                result = .success(
                    try await statusProvider.pullRequestCounts(
                        origin: origin,
                        branches: trackedBranches
                    )
                )
            } catch {
                result = .failure(String(describing: error))
            }
            guard !Task.isCancelled else { return }
            await self?.finishRefresh(
                repoId: repoId,
                generation: generation,
                correlationId: correlationId,
                result: result
            )
        }
        refreshState.inFlightTask = refreshTask
        refreshStateByRepoId[repoId] = refreshState
    }

    private func finishRefresh(
        repoId: UUID,
        generation: UInt64,
        correlationId: UUID?,
        result: RefreshResult
    ) async {
        guard var refreshState = refreshStateByRepoId[repoId], refreshState.generation == generation else {
            return
        }

        switch result {
        case .success(let countsByBranch):
            refreshState.consecutiveFailureCount = 0
            if refreshState.lastPublishedCountsByBranch != countsByBranch {
                refreshState.lastPublishedCountsByBranch = countsByBranch
                refreshStateByRepoId[repoId] = refreshState
                await emitForgeEvent(
                    repoId: repoId,
                    correlationId: correlationId,
                    event: .pullRequestCountsChanged(repoId: repoId, countsByBranch: countsByBranch)
                )
                guard
                    let latestRefreshState = refreshStateByRepoId[repoId],
                    latestRefreshState.generation == generation
                else { return }
                refreshState = latestRefreshState
            }
        case .failure(let errorDescription):
            refreshState.consecutiveFailureCount += 1
            refreshState.hasPendingRefresh = true
            refreshStateByRepoId[repoId] = refreshState
            await emitForgeEvent(
                repoId: repoId,
                correlationId: correlationId,
                event: .refreshFailed(repoId: repoId, error: errorDescription)
            )
            guard
                let latestRefreshState = refreshStateByRepoId[repoId],
                latestRefreshState.generation == generation
            else { return }
            refreshState = latestRefreshState
        }

        refreshState.inFlightTask = nil
        refreshStateByRepoId[repoId] = refreshState
        if refreshState.consecutiveFailureCount > 0 {
            scheduleBackoff(repoId: repoId, generation: generation)
        } else {
            startPendingRefreshIfNeeded(repoId: repoId)
        }
    }

    private func scheduleBackoff(repoId: UUID, generation: UInt64) {
        guard var refreshState = refreshStateByRepoId[repoId], refreshState.generation == generation else {
            return
        }
        let delay = self.delay
        let backoffDelay = AppPolicies.ForgeRefresh.failureBackoffDelay(
            forConsecutiveFailureCount: refreshState.consecutiveFailureCount
        )
        let backoffTask = Task { [weak self, delay] in
            do {
                try await delay.wait(backoffDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.finishBackoff(repoId: repoId, generation: generation)
        }
        refreshState.backoffTask = backoffTask
        refreshStateByRepoId[repoId] = refreshState
    }

    private func finishBackoff(repoId: UUID, generation: UInt64) {
        guard var refreshState = refreshStateByRepoId[repoId], refreshState.generation == generation else {
            return
        }
        refreshState.backoffTask = nil
        refreshStateByRepoId[repoId] = refreshState
        startPendingRefreshIfNeeded(repoId: repoId)
    }

    private func startPendingRefreshIfNeeded(repoId: UUID) {
        guard var refreshState = refreshStateByRepoId[repoId], refreshState.hasPendingRefresh else {
            return
        }
        let correlationId = refreshState.pendingCorrelationId
        refreshState.hasPendingRefresh = false
        refreshState.pendingCorrelationId = nil
        refreshStateByRepoId[repoId] = refreshState
        requestRefresh(repoId: repoId, correlationId: correlationId)
    }

    private func emitForgeEvent(
        repoId: UUID,
        correlationId: UUID?,
        event: ForgeEvent
    ) async {
        nextEnvelopeSequence += 1
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
