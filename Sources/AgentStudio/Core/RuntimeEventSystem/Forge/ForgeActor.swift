import AgentStudioInfrastructure
import Foundation
import os

package protocol ForgeStatusProvider: Sendable {
    func pullRequests(origin: String, branches: Set<String>) async throws -> [String: [ForgePullRequest]]
}

package struct ForgePullRequest: Equatable, Sendable {
    package let url: URL
    package let isOpen: Bool

    package init(url: URL, isOpen: Bool) {
        self.url = url
        self.isOpen = isOpen
    }
}

enum ForgeStatusProviderError: Error, Sendable {
    case unsupportedRemote(String)
    case commandFailed(message: String)
    case invalidResponse(String)
}

package struct GitHubCLIForgeStatusProvider: ForgeStatusProvider {
    private struct PullRequestRecord: Decodable {
        let headRefName: String
        let url: String
        let state: String
    }

    private let processExecutor: any ProcessExecutor

    package init(processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 8)) {
        self.processExecutor = processExecutor
    }

    package func pullRequests(origin: String, branches: Set<String>) async throws -> [String: [ForgePullRequest]] {
        let trackedBranches = Set(branches.filter { !$0.isEmpty })
        guard !trackedBranches.isEmpty else { return [:] }

        guard let repoSlug = RemoteIdentityNormalizer.extractSlug(origin) else {
            throw ForgeStatusProviderError.unsupportedRemote(origin)
        }

        var pullRequestsByBranch = Dictionary(uniqueKeysWithValues: trackedBranches.map { ($0, [ForgePullRequest]()) })
        for branch in trackedBranches.sorted() {
            let result = try await processExecutor.execute(
                command: "gh",
                args: [
                    "pr",
                    "list",
                    "--repo", repoSlug,
                    "--head", branch,
                    "--state", "all",
                    "--json", "headRefName,url,state",
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
            let pullRequests = try JSONDecoder().decode([PullRequestRecord].self, from: data)
            for pullRequest in pullRequests where pullRequest.headRefName == branch {
                guard let url = URL(string: pullRequest.url) else {
                    throw ForgeStatusProviderError.invalidResponse(
                        "gh returned an invalid pull request URL for branch \(pullRequest.headRefName)"
                    )
                }
                pullRequestsByBranch[branch, default: []].append(
                    ForgePullRequest(url: url, isOpen: pullRequest.state == "OPEN")
                )
            }
        }
        return pullRequestsByBranch
    }
}

package actor ForgeActor {
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
    private var refreshGenerationByRepoId: [UUID: UInt64] = [:]

    package init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        statusProvider: any ForgeStatusProvider,
        providerName: String = "github",
        envelopeClock: ContinuousClock = ContinuousClock(),
        pollInterval: Duration = .seconds(45),
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
    }

    package func start() async {
        if subscriptionTask == nil {
            let stream = await runtimeBus.subscribe(
                policy: .lossyNewest(subscriptionBufferLimit),
                subscriberName: "ForgeActor"
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

        let generation = advanceRefreshGeneration(for: repoId)
        repoOriginByRepoId[repoId] = trimmedRemote
        if branchesByRepoId[repoId] == nil {
            branchesByRepoId[repoId] = []
        }
        await refreshRepo(repoId: repoId, correlationId: nil, generation: generation)
    }

    package func unregister(repo repoId: UUID) async {
        _ = advanceRefreshGeneration(for: repoId)
        repoOriginByRepoId.removeValue(forKey: repoId)
        branchesByRepoId.removeValue(forKey: repoId)
    }

    package func refresh(repo repoId: UUID, correlationId: UUID? = nil) async {
        let generation = advanceRefreshGeneration(for: repoId)
        await refreshRepo(repoId: repoId, correlationId: correlationId, generation: generation)
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

        repoOriginByRepoId.removeAll(keepingCapacity: false)
        branchesByRepoId.removeAll(keepingCapacity: false)
        refreshGenerationByRepoId.removeAll(keepingCapacity: false)
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
            await unregister(repo: repoId)
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
            await refresh(repo: repoId)
        }
    }

    private func refreshRepo(repoId: UUID, correlationId: UUID?, generation: UInt64) async {
        guard !Task.isCancelled else { return }
        guard refreshGenerationByRepoId[repoId] == generation else { return }
        guard let origin = repoOriginByRepoId[repoId], !origin.isEmpty else { return }
        let trackedBranches = branchesByRepoId[repoId] ?? []

        do {
            let pullRequestsByBranch = try await statusProvider.pullRequests(
                origin: origin,
                branches: trackedBranches
            )
            guard !Task.isCancelled, refreshGenerationByRepoId[repoId] == generation else { return }
            await emitForgeEvent(
                repoId: repoId,
                correlationId: correlationId,
                event: .pullRequestsChanged(repoId: repoId, pullRequestsByBranch: pullRequestsByBranch)
            )
        } catch {
            guard !Task.isCancelled, refreshGenerationByRepoId[repoId] == generation else { return }
            await emitForgeEvent(
                repoId: repoId,
                correlationId: correlationId,
                event: .refreshFailed(repoId: repoId, error: String(describing: error))
            )
        }
    }

    private func advanceRefreshGeneration(for repoId: UUID) -> UInt64 {
        let generation = (refreshGenerationByRepoId[repoId] ?? 0) &+ 1
        refreshGenerationByRepoId[repoId] = generation
        return generation
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
