import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("ForgeActor")
struct ForgeActorTests {
    @Test("overlapping refreshes keep at most one provider call in flight per repo")
    func overlappingRefreshesKeepOneProviderCallInFlightPerRepo() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let provider = SuspendedForgeStatusProvider()
        let actor = ForgeActor(
            bus: bus,
            statusProvider: provider,
            providerName: "suspended",
            pollInterval: .seconds(60)
        )

        let registerTask = Task {
            await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
        }
        await provider.waitForStartedCallCount(1)
        let overlappingRefreshTask = Task { await actor.refresh(repo: repoId) }
        for _ in 0..<50 {
            await Task.yield()
        }

        #expect(await provider.maximumActiveCallCount == 1)

        await provider.finishNextCall(returning: [:])
        await provider.waitForStartedCallCount(2)
        await provider.finishNextCall(returning: [:])
        await registerTask.value
        await overlappingRefreshTask.value
        await actor.shutdown()
    }

    @Test("equal successful count maps publish only once")
    func equalSuccessfulCountMapsPublishOnlyOnce() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let observer = ObservedForgeEvents()
        let actor = ForgeActor(
            bus: bus,
            statusProvider: StubForgeStatusProvider(handler: { _, _ in ["main": 1] }),
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
        await observer.waitForPullRequestCount(1, repoId: repoId)
        await actor.refresh(repo: repoId)
        await actor.refresh(repo: repoId)
        for _ in 0..<50 {
            await Task.yield()
        }

        #expect(await observer.pullRequestCount(for: repoId) == 1)
        await actor.shutdown()
    }

    @Test("provider failures retry at exact exponential backoff deadlines")
    func providerFailuresRetryAtExactBackoffDeadlines() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let provider = SuspendedForgeStatusProvider()
        let clock = TestPushClock()
        let observer = ObservedForgeEvents()
        let actor = ForgeActor(
            bus: bus,
            statusProvider: provider,
            providerName: "suspended",
            pollInterval: .seconds(60),
            sleepClock: clock
        )
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
        await provider.waitForStartedCallCount(1)
        await provider.failNextCall()
        #expect(
            await eventually("first forge failure should publish") {
                await observer.refreshFailedCount(for: repoId) == 1
            })
        await clock.waitForPendingSleepCount()
        #expect(await provider.startedCount == 1)

        clock.advance(by: AppPolicies.ForgeRefresh.failureBackoffBaseDelay)
        await provider.waitForStartedCallCount(2)
        await provider.failNextCall()
        #expect(
            await eventually("second forge failure should publish") {
                await observer.refreshFailedCount(for: repoId) == 2
            })
        await clock.waitForPendingSleepCount()
        #expect(await provider.startedCount == 2)

        clock.advance(
            by: AppPolicies.ForgeRefresh.failureBackoffDelay(forConsecutiveFailureCount: 2)
        )
        await provider.waitForStartedCallCount(3)
        await provider.finishNextCall(returning: ["main": 1])
        await observer.waitForPullRequestCount(1, repoId: repoId)

        #expect(await provider.startedCount == 3)
        await actor.shutdown()
    }

    @Test("changed count map publishes after an equal result was suppressed")
    func changedCountMapPublishesAfterEqualSuppression() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let provider = SequencedForgeStatusProvider(
            results: [["main": 1], ["main": 1], ["main": 2]]
        )
        let observer = ObservedForgeEvents()
        let actor = ForgeActor(bus: bus, statusProvider: provider, providerName: "sequenced")
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
        await observer.waitForPullRequestCount(1, repoId: repoId)
        await actor.refresh(repo: repoId)
        await provider.waitForCallCount(2)
        await actor.refresh(repo: repoId)
        await provider.waitForCallCount(3)
        await observer.waitForPullRequestCount(2, repoId: repoId)

        #expect(await observer.pullRequestCount(for: repoId) == 2)
        #expect(await observer.lastPullRequestCounts(for: repoId) == ["main": 2])
        await actor.shutdown()
    }

    @Test("different repos may refresh concurrently")
    func differentReposMayRefreshConcurrently() async {
        let provider = SuspendedForgeStatusProvider()
        let actor = ForgeActor(
            bus: EventBus<RuntimeEnvelope>(),
            statusProvider: provider,
            providerName: "suspended"
        )

        await actor.register(repo: UUID(), remote: "git@github.com:askluna/first.git")
        await actor.register(repo: UUID(), remote: "git@github.com:askluna/second.git")
        await provider.waitForStartedCallCount(2)

        #expect(await provider.maximumActiveCallCount == 2)
        await provider.finishNextCall(returning: [:])
        await provider.finishNextCall(returning: [:])
        await actor.shutdown()
    }

    @Test("unregister cancels the repo provider flight")
    func unregisterCancelsRepoProviderFlight() async {
        let repoId = UUID()
        let provider = CancellationObservingForgeStatusProvider()
        let actor = ForgeActor(
            bus: EventBus<RuntimeEnvelope>(),
            statusProvider: provider,
            providerName: "cancellation-observing"
        )

        await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
        await provider.waitUntilStarted()
        await actor.unregister(repo: repoId)
        await provider.waitUntilCancelled()

        #expect(await provider.didObserveCancellation)
        await actor.shutdown()
    }

    @Test("reacts to originChanged and branchChanged by emitting pull request counts")
    func reactsToGitProjectorEvents() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let observer = ObservedForgeEvents()

        let actor = ForgeActor(
            bus: bus,
            statusProvider: StubForgeStatusProvider(handler: { _, branches in
                var counts: [String: Int] = [:]
                for branch in branches {
                    counts[branch] = 1
                }
                return counts
            }),
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        await actor.start()

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .originChanged(
                            repoId: repoId,
                            from: "",
                            to: "git@github.com:askluna/agent-studio.git"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: "main",
                            to: "feature/runtime"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )

        let receivedCounts = await eventually("forge counts event should be emitted") {
            await observer.lastPullRequestCounts(for: repoId)?["feature/runtime"] == 1
        }
        #expect(receivedCounts)

        await actor.shutdown()
    }

    @Test("emits refreshFailed when provider throws")
    func pollingFallbackErrorPath() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let observer = ObservedForgeEvents()

        enum ForgeProviderError: Error {
            case networkUnavailable
        }

        let actor = ForgeActor(
            bus: bus,
            statusProvider: StubForgeStatusProvider(handler: { _, _ in
                throw ForgeProviderError.networkUnavailable
            }),
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        await actor.start()

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .originChanged(
                            repoId: repoId,
                            from: "",
                            to: "git@github.com:askluna/agent-studio.git"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: "main",
                            to: "feature/runtime"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )

        let receivedFailure = await eventually("forge failure should be emitted") {
            await observer.refreshFailedCount(for: repoId) > 0
        }
        #expect(receivedFailure)

        await actor.shutdown()
    }

    @Test("register/unregister command-plane APIs control scope explicitly")
    func commandPlaneRegisterAndUnregister() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let observer = ObservedForgeEvents()

        let actor = ForgeActor(
            bus: bus,
            statusProvider: StubForgeStatusProvider(handler: { _, branches in
                var counts: [String: Int] = [:]
                for branch in branches {
                    counts[branch] = 2
                }
                return counts
            }),
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        await actor.start()

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: UUID(),
                            repoId: repoId,
                            from: "main",
                            to: "feature/runtime"
                        )
                    ),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        let registered = await eventually("command-plane register should emit counts") {
            await observer.lastPullRequestCounts(for: repoId)?["feature/runtime"] == 2
        }
        #expect(registered)

        await actor.unregister(repo: repoId)
        await actor.refresh(repo: repoId)
        let refreshFailureCount = await observer.refreshFailedCount(for: repoId)
        #expect(refreshFailureCount == 0)

        await actor.shutdown()
    }

    @Test("shutdown cancels subscriptions so post-shutdown events are ignored")
    func shutdownStopsConsumingBusEvents() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let observer = ObservedForgeEvents()

        let actor = ForgeActor(
            bus: bus,
            statusProvider: StubForgeStatusProvider(handler: { _, branches in
                var counts: [String: Int] = [:]
                for branch in branches {
                    counts[branch] = 1
                }
                return counts
            }),
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        await actor.start()

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observeTask = Task {
            for await envelope in stream {
                await observer.record(envelope)
            }
        }
        defer { observeTask.cancel() }

        await actor.shutdown()

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .originChanged(
                            repoId: repoId,
                            from: "",
                            to: "git@github.com:askluna/agent-studio.git"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: "main",
                            to: "feature/runtime"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )

        let emittedAfterShutdown = await observer.lastPullRequestCounts(for: repoId) != nil
        #expect(!emittedAfterShutdown)
    }

    private func eventually(
        _ description: String,
        maxTurns: Int = 200,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        Issue.record("\(description) timed out")
        return false
    }
}

private actor ObservedForgeEvents {
    private var pullRequestCountsByRepoId: [UUID: [String: Int]] = [:]
    private var pullRequestEventCountByRepoId: [UUID: Int] = [:]
    private var pullRequestCountWaitersByRepoId: [UUID: [(Int, CheckedContinuation<Void, Never>)]] = [:]
    private var refreshFailuresByRepoId: [UUID: Int] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard case .forge(let forgeEvent) = worktreeEnvelope.event else { return }
        switch forgeEvent {
        case .pullRequestCountsChanged(let repoId, let countsByBranch):
            pullRequestCountsByRepoId[repoId] = countsByBranch
            pullRequestEventCountByRepoId[repoId, default: 0] += 1
            let eventCount = pullRequestEventCountByRepoId[repoId, default: 0]
            let waiters = pullRequestCountWaitersByRepoId.removeValue(forKey: repoId) ?? []
            var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
            for (expectedCount, continuation) in waiters {
                if eventCount >= expectedCount {
                    continuation.resume()
                } else {
                    pendingWaiters.append((expectedCount, continuation))
                }
            }
            pullRequestCountWaitersByRepoId[repoId] = pendingWaiters
        case .refreshFailed(let repoId, _):
            refreshFailuresByRepoId[repoId, default: 0] += 1
        case .checksUpdated, .rateLimited:
            return
        }
    }

    func lastPullRequestCounts(for repoId: UUID) -> [String: Int]? {
        pullRequestCountsByRepoId[repoId]
    }

    func pullRequestCount(for repoId: UUID) -> Int {
        pullRequestEventCountByRepoId[repoId, default: 0]
    }

    func waitForPullRequestCount(_ expectedCount: Int, repoId: UUID) async {
        guard pullRequestEventCountByRepoId[repoId, default: 0] < expectedCount else { return }
        await withCheckedContinuation { continuation in
            pullRequestCountWaitersByRepoId[repoId, default: []].append((expectedCount, continuation))
        }
    }

    func refreshFailedCount(for repoId: UUID) -> Int {
        refreshFailuresByRepoId[repoId, default: 0]
    }
}

private actor SuspendedForgeStatusProvider: ForgeStatusProvider {
    private struct PendingCall {
        let continuation: CheckedContinuation<[String: Int], Error>
    }

    private var pendingCalls: [PendingCall] = []
    private var startedCallCount = 0
    private var activeCallCount = 0
    private var startedCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var maximumActiveCallCount = 0

    var startedCount: Int {
        startedCallCount
    }

    func pullRequestCounts(origin _: String, branches _: Set<String>) async throws -> [String: Int] {
        startedCallCount += 1
        activeCallCount += 1
        maximumActiveCallCount = max(maximumActiveCallCount, activeCallCount)
        resumeSatisfiedStartedCallWaiters()
        defer { activeCallCount -= 1 }
        return try await withCheckedThrowingContinuation { continuation in
            pendingCalls.append(PendingCall(continuation: continuation))
        }
    }

    func waitForStartedCallCount(_ expectedCount: Int) async {
        guard startedCallCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            startedCallWaiters.append((expectedCount, continuation))
        }
    }

    func finishNextCall(returning counts: [String: Int]) {
        let pendingCall = pendingCalls.removeFirst()
        pendingCall.continuation.resume(returning: counts)
    }

    func failNextCall() {
        let pendingCall = pendingCalls.removeFirst()
        pendingCall.continuation.resume(throwing: SuspendedProviderError.failed)
    }

    private func resumeSatisfiedStartedCallWaiters() {
        var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in startedCallWaiters {
            if startedCallCount >= expectedCount {
                continuation.resume()
            } else {
                pendingWaiters.append((expectedCount, continuation))
            }
        }
        startedCallWaiters = pendingWaiters
    }
}

private enum SuspendedProviderError: Error {
    case failed
}

private actor SequencedForgeStatusProvider: ForgeStatusProvider {
    private var results: [[String: Int]]
    private var callCount = 0
    private var callCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(results: [[String: Int]]) {
        self.results = results
    }

    func pullRequestCounts(origin _: String, branches _: Set<String>) async throws -> [String: Int] {
        let result = results.removeFirst()
        callCount += 1
        resumeSatisfiedCallCountWaiters()
        return result
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeSatisfiedCallCountWaiters() {
        var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in callCountWaiters {
            if callCount >= expectedCount {
                continuation.resume()
            } else {
                pendingWaiters.append((expectedCount, continuation))
            }
        }
        callCountWaiters = pendingWaiters
    }
}

private actor CancellationObservingForgeStatusProvider: ForgeStatusProvider {
    private var didStart = false
    private var didCancel = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    var didObserveCancellation: Bool {
        didCancel
    }

    func pullRequestCounts(origin _: String, branches _: Set<String>) async throws -> [String: Int] {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }

        while !Task.isCancelled {
            await Task.yield()
        }

        didCancel = true
        let pendingCancellationWaiters = cancellationWaiters
        cancellationWaiters.removeAll(keepingCapacity: false)
        for waiter in pendingCancellationWaiters {
            waiter.resume()
        }
        throw CancellationError()
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        guard !didCancel else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }
}
