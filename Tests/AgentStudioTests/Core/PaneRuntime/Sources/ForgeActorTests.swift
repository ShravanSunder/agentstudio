import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ForgeActor")
struct ForgeActorTests {
    @Test("GitHub forge lookup scopes every request to the tracked branch")
    func githubProviderScopesQueryToTrackedBranch() async throws {
        let executor = RecordingForgeProcessExecutor(
            result: ProcessResult(
                exitCode: 0,
                stdout:
                    "[{\"headRefName\":\"improve/ci-under-8-min\",\"url\":\"https://github.com/ShravanSunder/agent-vm/pull/175\",\"state\":\"MERGED\"}]",
                stderr: ""
            )
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: executor)

        let pullRequestsByBranch = try await provider.pullRequests(
            origin: "git@github.com:ShravanSunder/agent-vm.git",
            branches: ["improve/ci-under-8-min"]
        )

        #expect(
            pullRequestsByBranch["improve/ci-under-8-min"] == [
                ForgePullRequest(
                    url: URL(string: "https://github.com/ShravanSunder/agent-vm/pull/175")!,
                    isOpen: false
                )
            ]
        )

        #expect(
            executor.lastCall?.args == [
                "pr", "list",
                "--repo", "ShravanSunder/agent-vm",
                "--head", "improve/ci-under-8-min",
                "--state", "all",
                "--json", "headRefName,url,state",
                "--limit", "200",
            ]
        )
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

    @Test("originUnavailable unregisters the repository forge scope")
    func originUnavailableUnregistersForgeScope() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let observer = ObservedForgeEvents()

        let actor = ForgeActor(
            bus: bus,
            statusProvider: StubForgeStatusProvider(handler: { _, branches in
                Dictionary(uniqueKeysWithValues: branches.map { ($0, 1) })
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
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
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

        let initialEventsReceived = await eventually("initial forge refresh should be observed") {
            await observer.pullRequestChangeCount(for: repoId) >= 2
        }
        #expect(initialEventsReceived)
        let initialEventCount = await observer.pullRequestChangeCount(for: repoId)

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(.originUnavailable(repoId: repoId)),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: UUID(),
                            repoId: repoId,
                            from: "feature/runtime",
                            to: "feature/after-origin-unavailable"
                        )
                    ),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        for _ in 0..<100 {
            await Task.yield()
        }

        #expect(await observer.pullRequestChangeCount(for: repoId) == initialEventCount)
        await actor.shutdown()
    }

    @Test("drops a refresh result that belongs to an obsolete origin")
    func staleRefreshResultAfterOriginChangeIsDropped() async {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let provider = GatedForgeStatusProvider()
        let observer = ObservedForgeEvents()

        let actor = ForgeActor(
            bus: bus,
            statusProvider: provider,
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

        let oldOrigin = "git@github.com:old-owner/old-repo.git"
        let newOrigin = "git@github.com:new-owner/new-repo.git"
        let oldRegistration = Task {
            await actor.register(repo: repoId, remote: oldOrigin)
        }
        let firstRequest = await provider.nextRequest()
        #expect(firstRequest.origin == oldOrigin)

        let newRegistration = Task {
            await actor.register(repo: repoId, remote: newOrigin)
        }
        let secondRequest = await provider.nextRequest()
        #expect(secondRequest.origin == newOrigin)

        await provider.releaseNext(
            [
                "feature/runtime": [
                    ForgePullRequest(
                        url: URL(string: "https://github.com/old-owner/old-repo/pull/1")!,
                        isOpen: true
                    )
                ]
            ]
        )
        await provider.releaseNext(
            [
                "feature/runtime": [
                    ForgePullRequest(
                        url: URL(string: "https://github.com/new-owner/new-repo/pull/2")!,
                        isOpen: true
                    )
                ]
            ]
        )
        await oldRegistration.value
        await newRegistration.value

        let receivedCurrentResult = await eventually("current-origin forge refresh should be observed") {
            await observer.pullRequestChangeCount(for: repoId) >= 1
        }
        #expect(receivedCurrentResult)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await observer.pullRequestChangeCount(for: repoId) == 1)
        #expect(
            await observer.lastPullRequestURLs(for: repoId)?["feature/runtime"]
                == [URL(string: "https://github.com/new-owner/new-repo/pull/2")!]
        )

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

private final class RecordingForgeProcessExecutor: ProcessExecutor, @unchecked Sendable {
    let result: ProcessResult
    private(set) var calls: [Call] = []

    var lastCall: Call? {
        calls.last
    }

    struct Call: Equatable {
        let command: String
        let args: [String]
    }

    init(result: ProcessResult) {
        self.result = result
    }

    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        calls.append(Call(command: command, args: args))
        return result
    }
}

private actor GatedForgeStatusProvider: ForgeStatusProvider {
    struct Request: Sendable {
        let origin: String
        let branches: Set<String>
    }

    private var pendingRequests: [Request] = []
    private var requestWaiters: [CheckedContinuation<Request, Never>] = []
    private var resultWaiters: [CheckedContinuation<[String: [ForgePullRequest]], Never>] = []

    func pullRequests(origin: String, branches: Set<String>) async throws -> [String: [ForgePullRequest]] {
        let request = Request(origin: origin, branches: branches)
        if let waiter = requestWaiters.first {
            requestWaiters.removeFirst()
            waiter.resume(returning: request)
        } else {
            pendingRequests.append(request)
        }
        return await withCheckedContinuation { continuation in
            resultWaiters.append(continuation)
        }
    }

    func nextRequest() async -> Request {
        if let request = pendingRequests.first {
            pendingRequests.removeFirst()
            return request
        }
        return await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseNext(_ result: [String: [ForgePullRequest]]) {
        precondition(!resultWaiters.isEmpty)
        resultWaiters.removeFirst().resume(returning: result)
    }
}

private actor ObservedForgeEvents {
    private var pullRequestCountsByRepoId: [UUID: [String: Int]] = [:]
    private var pullRequestChangeCountsByRepoId: [UUID: Int] = [:]
    private var pullRequestURLsByRepoId: [UUID: [String: [URL]]] = [:]
    private var refreshFailuresByRepoId: [UUID: Int] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard case .forge(let forgeEvent) = worktreeEnvelope.event else { return }
        switch forgeEvent {
        case .pullRequestsChanged(let repoId, let pullRequestsByBranch):
            pullRequestChangeCountsByRepoId[repoId, default: 0] += 1
            pullRequestCountsByRepoId[repoId] = pullRequestsByBranch.mapValues { pullRequests in
                pullRequests.filter(\.isOpen).count
            }
            pullRequestURLsByRepoId[repoId] = pullRequestsByBranch.mapValues { pullRequests in
                pullRequests.map(\.url)
            }
        case .refreshFailed(let repoId, _):
            refreshFailuresByRepoId[repoId, default: 0] += 1
        case .checksUpdated, .rateLimited:
            return
        }
    }

    func lastPullRequestCounts(for repoId: UUID) -> [String: Int]? {
        pullRequestCountsByRepoId[repoId]
    }

    func pullRequestChangeCount(for repoId: UUID) -> Int {
        pullRequestChangeCountsByRepoId[repoId, default: 0]
    }

    func lastPullRequestURLs(for repoId: UUID) -> [String: [URL]]? {
        pullRequestURLsByRepoId[repoId]
    }

    func refreshFailedCount(for repoId: UUID) -> Int {
        refreshFailuresByRepoId[repoId, default: 0]
    }
}
