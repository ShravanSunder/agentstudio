import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ForgeActor")
struct ForgeActorTests {
    @Test("missing demanded branch starts an immediate repository refresh")
    func missingDemandStartsImmediateRefresh() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let pullRequestURL = URL(string: "https://github.com/acme/studio/pull/42")!

        await fixture.actor.register(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/acme-studio"),
            branch: "feature/toolbar"
        )
        await fixture.actor.setOrigin(repo: repoId, remote: "git@github.com:acme/studio.git")
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))

        await fixture.provider.resolve(
            callAt: 0,
            with: .complete([
                ForgePullRequest(headRefName: "feature/toolbar", url: pullRequestURL)
            ])
        )

        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/toolbar",
                expected: PullRequestFacts(openCount: 1, exactOpenURL: pullRequestURL)
            )
        )
        await fixture.actor.shutdown()
    }

    @Test("one active request admits only one latest-scope follow-up")
    func oneActiveRequestAndOneLatestFollowUp() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let latestWorktreeId = UUIDv7.generate()

        await fixture.register(
            repoId: repoId,
            worktrees: [
                (firstWorktreeId, "feature/first"),
                (secondWorktreeId, "feature/second"),
                (latestWorktreeId, "feature/latest"),
            ]
        )
        await fixture.actor.setDemand(worktreeIds: [firstWorktreeId])
        #expect(await fixture.provider.waitForCallCount(1))

        await fixture.actor.setDemand(worktreeIds: [secondWorktreeId])
        await fixture.actor.setDemand(worktreeIds: [latestWorktreeId])
        #expect(await fixture.provider.callCount == 1)

        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(await fixture.provider.waitForCallCount(2))
        #expect(await fixture.provider.callCount == 2)

        let latestURL = URL(string: "https://github.com/acme/studio/pull/99")!
        await fixture.provider.resolve(
            callAt: 1,
            with: .complete([
                ForgePullRequest(headRefName: "feature/latest", url: latestURL)
            ])
        )
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/latest",
                expected: PullRequestFacts(openCount: 1, exactOpenURL: latestURL)
            )
        )
        #expect(await fixture.events.facts(for: repoId, branch: "feature/second") == nil)
        await fixture.actor.shutdown()
    }

    @Test("fresh demand waits for the single three-minute deadline")
    func freshDemandWaitsForDeadline() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/fresh")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/fresh",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )
        await fixture.clock.waitForPendingSleepCount(atLeast: 1)

        fixture.advance(by: .seconds(179))
        await Task.yield()
        #expect(await fixture.provider.callCount == 1)

        fixture.advance(by: .seconds(1))
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
    }

    @Test("empty demand cancels future automatic GitHub work")
    func emptyDemandStopsAutomaticRefresh() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/visible")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/visible",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )

        await fixture.actor.setDemand(worktreeIds: [])
        fixture.advance(by: .seconds(600))
        await Task.yield()

        #expect(await fixture.provider.callCount == 1)
        await fixture.actor.shutdown()
    }

    @Test("rate-limit retry respects retry-after and the three-minute minimum")
    func rateLimitBackoffControlsDeadline() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/rate-limit")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .rateLimited(retryAfterSeconds: 300))
        #expect(await fixture.events.waitForRateLimit(repoId: repoId, retryAfterSeconds: 300))
        await fixture.clock.waitForPendingSleepCount(atLeast: 1)

        fixture.advance(by: .seconds(299))
        await Task.yield()
        #expect(await fixture.provider.callCount == 1)

        fixture.advance(by: .seconds(1))
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
    }

    @Test("origin replacement invalidates prior facts and rejects the obsolete completion")
    func originReplacementRejectsObsoleteCompletion() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/origin")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))

        await fixture.actor.setOrigin(repo: repoId, remote: "https://github.com/acme/replacement.git")
        #expect(await fixture.events.waitForRepositoryInvalidation(repoId: repoId))
        #expect(await fixture.provider.waitForCallCount(2))

        let obsoleteURL = URL(string: "https://github.com/acme/studio/pull/1")!
        await fixture.provider.resolve(
            callAt: 0,
            with: .complete([ForgePullRequest(headRefName: "feature/origin", url: obsoleteURL)])
        )
        let currentURL = URL(string: "https://github.com/acme/replacement/pull/2")!
        await fixture.provider.resolve(
            callAt: 1,
            with: .complete([ForgePullRequest(headRefName: "feature/origin", url: currentURL)])
        )

        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/origin",
                expected: PullRequestFacts(openCount: 1, exactOpenURL: currentURL)
            )
        )
        #expect(await fixture.events.containsExactURL(obsoleteURL) == false)
        await fixture.actor.shutdown()
    }

    @Test("only final live membership removal invalidates a shared branch")
    func finalMembershipRemovalInvalidatesSharedBranch() async {
        let fixture = await ForgeActorFixture.make()
        defer { fixture.stopObserving() }
        let repoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()

        await fixture.register(
            repoId: repoId,
            worktrees: [
                (firstWorktreeId, "feature/shared"),
                (secondWorktreeId, "feature/shared"),
            ]
        )
        await fixture.actor.unregister(worktreeId: firstWorktreeId)
        #expect(await fixture.events.invalidatedBranches(for: repoId).isEmpty)

        await fixture.actor.unregister(worktreeId: secondWorktreeId)

        #expect(await fixture.events.waitForBranchInvalidation(repoId: repoId, branch: "feature/shared"))
        await fixture.actor.shutdown()
    }
}

struct ForgeActorFixture {
    let bus: EventBus<RuntimeEnvelope>
    let actor: ForgeActor
    let provider: GatedForgeStatusProvider
    let events: ObservedForgeEvents
    let clock: TestPushClock
    let monotonicNow: ManualForgeMonotonicNow
    let observationTask: Task<Void, Never>

    static func make() async -> Self {
        let bus = EventBus<RuntimeEnvelope>()
        let provider = GatedForgeStatusProvider()
        let events = ObservedForgeEvents()
        let clock = TestPushClock()
        let monotonicNow = ManualForgeMonotonicNow()
        let actor = ForgeActor(
            bus: bus,
            statusProvider: provider,
            providerName: "stub",
            monotonicNow: { monotonicNow.value },
            sleepClock: clock
        )
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let observationTask = Task {
            for await envelope in stream {
                await events.record(envelope)
            }
        }
        await actor.start()
        return Self(
            bus: bus,
            actor: actor,
            provider: provider,
            events: events,
            clock: clock,
            monotonicNow: monotonicNow,
            observationTask: observationTask
        )
    }

    func register(repoId: UUID, worktrees: [(UUID, String)]) async {
        for (index, worktree) in worktrees.enumerated() {
            await actor.register(
                worktreeId: worktree.0,
                repoId: repoId,
                rootPath: URL(fileURLWithPath: "/tmp/acme-studio-\(index)"),
                branch: worktree.1
            )
        }
        await actor.setOrigin(repo: repoId, remote: "git@github.com:acme/studio.git")
    }

    func advance(by duration: Duration) {
        monotonicNow.advance(by: duration)
        clock.advance(by: duration)
    }

    func stopObserving() {
        observationTask.cancel()
    }
}

final class ManualForgeMonotonicNow: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed = Duration.zero

    var value: Duration { lock.withLock { elapsed } }

    func advance(by duration: Duration) {
        lock.withLock { elapsed += duration }
    }
}

actor GatedForgeStatusProvider: ForgeStatusProvider {
    private struct PendingCall {
        let origin: String
        let continuation: CheckedContinuation<ForgePullRequestQueryOutcome, Never>
    }

    private var calls: [PendingCall] = []

    var callCount: Int { calls.count }

    func pullRequests(origin: String) async -> ForgePullRequestQueryOutcome {
        await withCheckedContinuation { continuation in
            calls.append(PendingCall(origin: origin, continuation: continuation))
        }
    }

    func resolve(callAt index: Int, with outcome: ForgePullRequestQueryOutcome) {
        calls[index].continuation.resume(returning: outcome)
    }

    func waitForCallCount(_ expectedCount: Int, maxTurns: Int = 500) async -> Bool {
        for _ in 0..<maxTurns {
            if calls.count >= expectedCount { return true }
            await Task.yield()
        }
        Issue.record("Expected \(expectedCount) Forge provider calls, received \(calls.count)")
        return false
    }
}

actor ObservedForgeEvents {
    private var recordedEvents: [ForgeEvent] = []

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope,
            case .forge(let forgeEvent) = worktreeEnvelope.event
        else { return }
        recordedEvents.append(forgeEvent)
    }

    func facts(for repoId: UUID, branch: String) -> PullRequestFacts? {
        for event in recordedEvents.reversed() {
            guard case .pullRequestsChanged(let eventRepoId, let factsByBranch) = event,
                eventRepoId == repoId
            else { continue }
            if let facts = factsByBranch[branch] { return facts }
        }
        return nil
    }

    func waitForFacts(
        repoId: UUID,
        branch: String,
        expected: PullRequestFacts,
        maxTurns: Int = 500
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if facts(for: repoId, branch: branch) == expected { return true }
            await Task.yield()
        }
        Issue.record("Expected Forge facts for branch \(branch)")
        return false
    }

    func invalidatedBranches(for repoId: UUID) -> Set<String> {
        recordedEvents.reduce(into: []) { result, event in
            guard case .pullRequestBranchesInvalidated(let eventRepoId, let branches) = event,
                eventRepoId == repoId
            else { return }
            result.formUnion(branches)
        }
    }

    func waitForBranchInvalidation(repoId: UUID, branch: String, maxTurns: Int = 500) async -> Bool {
        for _ in 0..<maxTurns {
            if invalidatedBranches(for: repoId).contains(branch) { return true }
            await Task.yield()
        }
        Issue.record("Expected branch invalidation for \(branch)")
        return false
    }

    func waitForRepositoryInvalidation(repoId: UUID, maxTurns: Int = 500) async -> Bool {
        for _ in 0..<maxTurns {
            if recordedEvents.contains(where: { event in
                guard case .pullRequestRepositoryInvalidated(let eventRepoId) = event else { return false }
                return eventRepoId == repoId
            }) {
                return true
            }
            await Task.yield()
        }
        Issue.record("Expected repository invalidation")
        return false
    }

    func repositoryInvalidationCount(repoId: UUID) -> Int {
        recordedEvents.count { event in
            guard case .pullRequestRepositoryInvalidated(let eventRepoId) = event else { return false }
            return eventRepoId == repoId
        }
    }

    func waitForRepositoryInvalidationCount(
        repoId: UUID,
        expectedCount: Int,
        maxTurns: Int = 500
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if repositoryInvalidationCount(repoId: repoId) == expectedCount { return true }
            await Task.yield()
        }
        Issue.record("Expected \(expectedCount) repository invalidations")
        return false
    }

    func waitForRefreshFailure(repoId: UUID, maxTurns: Int = 500) async -> Bool {
        for _ in 0..<maxTurns {
            if recordedEvents.contains(where: { event in
                guard case .refreshFailed(let eventRepoId, _) = event else { return false }
                return eventRepoId == repoId
            }) {
                return true
            }
            await Task.yield()
        }
        Issue.record("Expected Forge refresh failure")
        return false
    }

    func waitForRateLimit(repoId: UUID, retryAfterSeconds: Int, maxTurns: Int = 500) async -> Bool {
        for _ in 0..<maxTurns {
            if recordedEvents.contains(where: { event in
                guard case .rateLimited(let eventRepoId, let eventRetryAfter) = event else { return false }
                return eventRepoId == repoId && eventRetryAfter == retryAfterSeconds
            }) {
                return true
            }
            await Task.yield()
        }
        Issue.record("Expected typed Forge rate limit")
        return false
    }

    func containsExactURL(_ url: URL) -> Bool {
        recordedEvents.contains { event in
            guard case .pullRequestsChanged(_, let factsByBranch) = event else { return false }
            return factsByBranch.values.contains { $0.exactOpenURL == url }
        }
    }
}
