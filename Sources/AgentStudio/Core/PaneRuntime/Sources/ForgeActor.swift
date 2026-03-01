import Foundation
import os

protocol ForgeStatusProvider: Sendable {
    func pullRequestCounts(origin: String, branches: Set<String>) async throws -> [String: Int]
}

struct NoopForgeStatusProvider: ForgeStatusProvider {
    func pullRequestCounts(origin _: String, branches _: Set<String>) async throws -> [String: Int] {
        [:]
    }
}

struct StubForgeStatusProvider: ForgeStatusProvider {
    let handler: @Sendable (String, Set<String>) async throws -> [String: Int]

    init(handler: @escaping @Sendable (String, Set<String>) async throws -> [String: Int]) {
        self.handler = handler
    }

    func pullRequestCounts(origin: String, branches: Set<String>) async throws -> [String: Int] {
        try await handler(origin, branches)
    }
}

extension ForgeStatusProvider where Self == StubForgeStatusProvider {
    static func stub(
        _ handler: @escaping @Sendable (String, Set<String>) async throws -> [String: Int]
    ) -> StubForgeStatusProvider {
        StubForgeStatusProvider(handler: handler)
    }
}

actor ForgeActor {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "ForgeActor")

    private let runtimeBus: EventBus<RuntimeEnvelope>
    private let statusProvider: any ForgeStatusProvider
    private let providerName: String
    private let envelopeClock: ContinuousClock
    private let pollInterval: Duration
    private let sleepClock: any Clock<Duration>
    private let subscriptionBufferLimit: Int

    private var subscriptionTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var nextEnvelopeSequence: UInt64 = 0
    private var repoOriginByRepoId: [UUID: String] = [:]
    private var branchesByRepoId: [UUID: Set<String>] = [:]

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        statusProvider: any ForgeStatusProvider = NoopForgeStatusProvider(),
        providerName: String = "noop",
        envelopeClock: ContinuousClock = ContinuousClock(),
        pollInterval: Duration = .seconds(45),
        sleepClock: any Clock<Duration> = ContinuousClock(),
        subscriptionBufferLimit: Int = 256
    ) {
        self.runtimeBus = bus
        self.statusProvider = statusProvider
        self.providerName = providerName
        self.envelopeClock = envelopeClock
        self.pollInterval = pollInterval
        self.sleepClock = sleepClock
        self.subscriptionBufferLimit = subscriptionBufferLimit
    }

    isolated deinit {
        subscriptionTask?.cancel()
        pollingTask?.cancel()
    }

    func start() async {
        if subscriptionTask == nil {
            let stream = await runtimeBus.subscribe(
                bufferingPolicy: .bufferingNewest(subscriptionBufferLimit)
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
            pollingTask = Task { [weak self] in
                guard let self else { return }
                await self.pollLoop()
            }
        }
    }

    func shutdown() async {
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
            await refreshRepo(repoId: repoId, correlationId: correlationId)
        case .originChanged(_, _, let to):
            repoOriginByRepoId[repoId] = to
            await refreshRepo(repoId: repoId, correlationId: correlationId)
        case .worktreeDiscovered(_, _, let branch, _):
            if !branch.isEmpty {
                branchesByRepoId[repoId, default: []].insert(branch)
            }
        case .worktreeRemoved, .diffAvailable:
            return
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                try await sleepClock.sleep(for: pollInterval)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.warning(
                    "Unexpected forge polling sleep failure: \(String(describing: error), privacy: .public)"
                )
                continue
            }

            guard !Task.isCancelled else { return }
            let repoIds = Array(repoOriginByRepoId.keys)
            for repoId in repoIds {
                await refreshRepo(repoId: repoId, correlationId: nil)
            }
        }
    }

    private func refreshRepo(repoId: UUID, correlationId: UUID?) async {
        guard !Task.isCancelled else { return }
        guard let origin = repoOriginByRepoId[repoId], !origin.isEmpty else { return }
        let trackedBranches = branchesByRepoId[repoId] ?? []

        do {
            let countsByBranch = try await statusProvider.pullRequestCounts(
                origin: origin,
                branches: trackedBranches
            )
            await emitForgeEvent(
                repoId: repoId,
                correlationId: correlationId,
                event: .pullRequestCountsChanged(repoId: repoId, countsByBranch: countsByBranch)
            )
        } catch {
            await emitForgeEvent(
                repoId: repoId,
                correlationId: correlationId,
                event: .refreshFailed(repoId: repoId, error: String(describing: error))
            )
        }
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
