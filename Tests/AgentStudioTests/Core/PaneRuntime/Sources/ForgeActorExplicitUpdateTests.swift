import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ForgeActor explicit updates")
struct ForgeActorExplicitUpdateTests {
    @Test("explicit repository update reports a genuine provider failure")
    func reportsProviderFailure() async throws {
        let fixture = await ForgeActorFixture.make()
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        await fixture.register(repoId: repoID, worktrees: [(worktreeID, "feature/failure")])
        let lease = try #require(
            await fixture.actor.startExplicitRepositoryUpdate(
                repoId: repoID,
                attemptId: UUIDv7.generate()
            ).acceptedLease
        )
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .failed(message: "offline"))
        #expect(await lease.settlement() == .failed)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("explicit repository update follows a current represented branch supersession")
    func followsBranchSupersession() async throws {
        let fixture = await ForgeActorFixture.make()
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        await fixture.register(repoId: repoID, worktrees: [(worktreeID, "feature/one")])
        let lease = try #require(
            await fixture.actor.startExplicitRepositoryUpdate(
                repoId: repoID,
                attemptId: UUIDv7.generate()
            ).acceptedLease
        )
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.actor.register(
            worktreeId: worktreeID,
            repoId: repoID,
            rootPath: URL(fileURLWithPath: "/tmp/forge-explicit-supersession"),
            branch: "feature/two"
        )
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(await fixture.provider.waitForCallCount(2))
        #expect(await fixture.provider.demandedBranchSets.last == ["feature/two"])
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        #expect(await lease.settlement() == .completed)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("explicit repository update remains unsettled through rate-limit backoff")
    func remainsUnsettledThroughRateLimit() async throws {
        let fixture = await ForgeActorFixture.make()
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        await fixture.register(repoId: repoID, worktrees: [(worktreeID, "feature/rate-limited")])
        let lease = try #require(
            await fixture.actor.startExplicitRepositoryUpdate(
                repoId: repoID,
                attemptId: UUIDv7.generate()
            ).acceptedLease
        )
        #expect(await fixture.provider.waitForCallCount(1))
        let settlementRecorder = ForgeExplicitSettlementRecorder()
        let settlementTask = Task {
            await settlementRecorder.record(await lease.settlement())
        }
        await fixture.provider.resolve(callAt: 0, with: .rateLimited(retryAfterSeconds: 300))
        await fixture.clock.waitForPendingSleepCount(atLeast: 1)
        for _ in 0..<300 { await Task.yield() }
        #expect(await settlementRecorder.outcomes.isEmpty)
        fixture.advance(by: .seconds(299))
        await Task.yield()
        #expect(await fixture.provider.callCount == 1)
        fixture.advance(by: .seconds(1))
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await settlementTask.value
        #expect(await settlementRecorder.outcomes == [.completed])
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("explicit repository update without origin or represented branch is not applicable")
    func withoutScopeIsNotApplicable() async {
        let fixture = await ForgeActorFixture.make()
        let admission = await fixture.actor.startExplicitRepositoryUpdate(
            repoId: UUIDv7.generate(),
            attemptId: UUIDv7.generate()
        )
        #expect(admission.acceptedLease == nil)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("cold explicit repository update uses represented branches and waits for provider settlement")
    func coldUpdateUsesRepresentedBranches() async throws {
        let fixture = await ForgeActorFixture.make()
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        await fixture.register(repoId: repoID, worktrees: [(worktreeID, "feature/cold")])
        let lease = try #require(
            await fixture.actor.startExplicitRepositoryUpdate(
                repoId: repoID,
                attemptId: UUIDv7.generate()
            ).acceptedLease
        )
        #expect(await fixture.provider.waitForCallCount(1))
        #expect(await fixture.provider.demandedBranchSets == [["feature/cold"]])
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(await lease.settlement() == .completed)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }
}

private actor ForgeExplicitSettlementRecorder {
    private(set) var outcomes: [RepositoryFactSourceUpdateOutcome] = []

    func record(_ outcome: RepositoryFactSourceUpdateOutcome) {
        outcomes.append(outcome)
    }
}
