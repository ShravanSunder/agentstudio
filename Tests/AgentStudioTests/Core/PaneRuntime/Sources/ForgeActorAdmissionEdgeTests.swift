import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ForgeActor admission edges")
struct ForgeActorAdmissionEdgeTests {
    @Test("truncated repository result preserves facts and waits for the minimum retry deadline")
    func truncatedResultPreservesFactsAndBacksOff() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let pullRequestURL = URL(string: "https://github.com/acme/studio/pull/42")!

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/truncated")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(
            callAt: 0,
            with: .complete([ForgePullRequest(headRefName: "feature/truncated", url: pullRequestURL)])
        )
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/truncated",
                expected: PullRequestFacts(openCount: 1, exactOpenURL: pullRequestURL)
            )
        )

        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .truncated)
        #expect(await fixture.events.waitForRefreshFailure(repoId: repoId))
        #expect(
            await fixture.events.facts(for: repoId, branch: "feature/truncated")
                == PullRequestFacts(openCount: 1, exactOpenURL: pullRequestURL)
        )
        await fixture.clock.waitForPendingSleepCount(atLeast: 1)

        fixture.advance(by: .seconds(179))
        await Task.yield()
        #expect(await fixture.provider.callCount == 2)
        fixture.advance(by: .seconds(1))
        #expect(await fixture.provider.waitForCallCount(3))
        await fixture.provider.resolve(callAt: 2, with: .complete([]))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("ordinary failure preserves facts and manual refresh cannot bypass backoff")
    func ordinaryFailurePreservesFactsAndManualRefreshRespectsBackoff() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/failure")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailure(repoId: repoId))

        await fixture.actor.refresh(repo: repoId)
        await Task.yield()
        #expect(await fixture.provider.callCount == 1)

        await fixture.clock.waitForPendingSleepCount(atLeast: 1)
        fixture.advance(by: .seconds(180))
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/failure",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("registration schedules the freshness deadline when demand arrived before membership")
    func registrationSchedulesDeadlineForPreexistingDemand() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let laterWorktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(firstWorktreeId, "feature/first")])
        await fixture.actor.setDemand(worktreeIds: [firstWorktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/first",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )

        await fixture.actor.setDemand(worktreeIds: [laterWorktreeId])
        await fixture.actor.register(
            worktreeId: laterWorktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/acme-later"),
            branch: "feature/later"
        )

        await fixture.clock.waitForPendingSleepCount(atLeast: 1)

        fixture.advance(by: .seconds(180))
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("shutdown cannot admit a pending follow-up after provider cancellation")
    func shutdownRejectsPendingFollowUp() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/shutdown")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.callCount == 1)

        let shutdownTask = Task {
            await fixture.actor.shutdown()
        }
        await Task.yield()
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        await shutdownTask.value

        #expect(await fixture.provider.callCount == 1)
        await fixture.stopObserving()
    }

    @Test("multiple pull requests on one branch do not produce an arbitrary exact URL")
    func multiplePullRequestsDoNotProduceExactURL() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/ambiguous")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(
            callAt: 0,
            with: .complete([
                ForgePullRequest(
                    headRefName: "feature/ambiguous",
                    url: URL(string: "https://github.com/acme/studio/pull/41")!
                ),
                ForgePullRequest(
                    headRefName: "feature/ambiguous",
                    url: URL(string: "https://github.com/acme/studio/pull/42")!
                ),
            ])
        )

        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/ambiguous",
                expected: PullRequestFacts(openCount: 2, exactOpenURL: nil)
            )
        )
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("manual refresh bypasses freshness when no rate backoff is open")
    func manualRefreshBypassesFreshness() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/manual")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/manual",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )

        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("path-only discovery updates only matching known membership and removal is inert")
    func pathOnlyDiscoveryMatchesKnownMembership() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/acme-path-match")

        await fixture.actor.register(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: rootPath,
            branch: "feature/old"
        )
        _ = await fixture.bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .worktreeDiscovered(
                            repoId: repoId,
                            worktreePath: URL(fileURLWithPath: "/tmp/unrelated"),
                            branch: "feature/unrelated",
                            isMain: false
                        )
                    ),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        _ = await fixture.bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .worktreeDiscovered(
                            repoId: repoId,
                            worktreePath: rootPath,
                            branch: "feature/matched",
                            isMain: false
                        )
                    ),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        #expect(await fixture.events.waitForBranchInvalidation(repoId: repoId, branch: "feature/old"))

        _ = await fixture.bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(.worktreeRemoved(repoId: repoId, worktreePath: rootPath)),
                    repoId: repoId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        await fixture.actor.setOrigin(repo: repoId, remote: "git@github.com:acme/studio.git")
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/matched",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )
        #expect(await fixture.events.invalidatedBranches(for: repoId).contains("feature/unrelated") == false)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("a blocked provider cannot restore facts after the final branch membership switches")
    func blockedProviderCannotRestoreDepartedBranchFacts() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let departedBranchURL = URL(string: "https://github.com/acme/studio/pull/41")!

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/old")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))

        _ = await fixture.bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: "feature/old",
                            to: "feature/new"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        #expect(await fixture.events.waitForBranchInvalidation(repoId: repoId, branch: "feature/old"))

        await fixture.provider.resolve(
            callAt: 0,
            with: .complete([
                ForgePullRequest(headRefName: "feature/old", url: departedBranchURL)
            ])
        )
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/new",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )
        #expect(await fixture.events.facts(for: repoId, branch: "feature/old") == nil)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("origin loss and repository removal each invalidate repository facts")
    func originLossAndRepositoryRemovalInvalidateFacts() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/origin")])
        _ = await fixture.bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(.originUnavailable(repoId: repoId)),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        #expect(await fixture.events.waitForRepositoryInvalidation(repoId: repoId))
        #expect(await fixture.events.repositoryInvalidationCount(repoId: repoId) == 1)

        await fixture.actor.removeRepository(repo: repoId)
        #expect(await fixture.events.waitForRepositoryInvalidationCount(repoId: repoId, expectedCount: 2))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }
}
