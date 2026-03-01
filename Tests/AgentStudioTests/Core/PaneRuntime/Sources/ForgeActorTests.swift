import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("ForgeActor")
struct ForgeActorTests {
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

        let stream = await bus.subscribe()
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

        let stream = await bus.subscribe()
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

        let stream = await bus.subscribe()
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
                        .worktreeDiscovered(
                            repoId: repoId,
                            worktreePath: URL(fileURLWithPath: "/tmp/repo"),
                            branch: "feature/runtime",
                            isMain: false
                        )
                    ),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )

        await actor.register(repo: repoId, remote: "git@github.com:askluna/agent-studio.git")
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

        let stream = await bus.subscribe()
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

        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await observer.lastPullRequestCounts(for: repoId) == nil)
    }

    private func eventually(
        _ description: String,
        maxAttempts: Int = 200,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            if await condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        Issue.record("\(description) timed out")
        return false
    }
}

private actor ObservedForgeEvents {
    private var pullRequestCountsByRepoId: [UUID: [String: Int]] = [:]
    private var refreshFailuresByRepoId: [UUID: Int] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard case .forge(let forgeEvent) = worktreeEnvelope.event else { return }
        switch forgeEvent {
        case .pullRequestCountsChanged(let repoId, let countsByBranch):
            pullRequestCountsByRepoId[repoId] = countsByBranch
        case .refreshFailed(let repoId, _):
            refreshFailuresByRepoId[repoId, default: 0] += 1
        case .checksUpdated, .rateLimited:
            return
        }
    }

    func lastPullRequestCounts(for repoId: UUID) -> [String: Int]? {
        pullRequestCountsByRepoId[repoId]
    }

    func refreshFailedCount(for repoId: UUID) -> Int {
        refreshFailuresByRepoId[repoId, default: 0]
    }
}
