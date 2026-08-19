import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ForgeActor admission edges")
struct ForgeActorAdmissionEdgeTests {
    @Test("provider request publishes bounded loading edges around a successful query")
    func providerRequestPublishesLoadingEdgesAroundSuccess() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/loading")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])

        #expect(await fixture.provider.waitForCallCount(1))
        #expect(await fixture.events.waitForLoadingStates(repoId: repoId, expected: [true]))

        await fixture.provider.resolve(callAt: 0, with: .complete([]))

        #expect(await fixture.events.waitForLoadingStates(repoId: repoId, expected: [true, false]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/loading",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("failed provider request clears loading before entering backoff")
    func failedProviderRequestClearsLoadingBeforeBackoff() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/failure")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])

        #expect(await fixture.provider.waitForCallCount(1))
        #expect(await fixture.events.waitForLoadingStates(repoId: repoId, expected: [true]))
        await fixture.provider.resolve(callAt: 0, with: .failed(message: "offline"))

        #expect(await fixture.events.waitForLoadingStates(repoId: repoId, expected: [true, false]))
        #expect(await fixture.events.waitForRefreshFailure(repoId: repoId))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

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

    @Test("a detached-HEAD worktree never issues a forge query even with an origin and demand")
    func detachedHeadWorktreeNeverIssuesForgeQuery() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let detachedWorktreeId = UUIDv7.generate()

        // Detached HEAD reaches ForgeActor as a nil branch (WorkspaceCacheCoordinator's
        // `snapshot.branch ?? ""` coercion is a separate downstream consumer of the
        // same bus event, not something ForgeActor itself performs).
        await fixture.actor.register(
            worktreeId: detachedWorktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/acme-detached"),
            branch: nil
        )
        await fixture.actor.setOrigin(repo: repoId, remote: "git@github.com:acme/studio.git")
        await fixture.actor.setDemand(worktreeIds: [detachedWorktreeId])

        // No branch means no demanded branch to query, regardless of origin
        // or demand; advancing well past every backoff/freshness window must
        // not eventually admit a query either.
        fixture.advance(by: .seconds(600))
        await Task.yield()
        #expect(await fixture.provider.callCount == 0)

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

    @Test("same-scope upstream facts during a request retain a deadline follow-up")
    func sameScopeUpstreamFactsRetainDeadlineFollowUp() async {
        let performanceRecorder = ForgePerformanceRecorderSpy()
        let fixture = await ForgeActorFixture.make(performanceTraceRecorder: performanceRecorder)
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/acme-forge-pending-intent")
        let branch = "feature/pending-intent"

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, branch)])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))

        _ = await fixture.bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .snapshotChanged(
                            snapshot: GitWorkingTreeSnapshot(
                                worktreeId: worktreeId,
                                repoId: repoId,
                                rootPath: rootPath,
                                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                                branch: branch
                            )
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        )
        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        await fixture.clock.waitForPendingSleepCount(atLeast: 1)
        #expect(await fixture.provider.callCount == 1)

        #expect(performanceRecorder.outcomes == ["deferred"])

        fixture.advance(by: AppPolicies.ForgeRefresh.pendingFollowUpDelay)
        #expect(await fixture.provider.waitForCallCount(2))
        #expect(performanceRecorder.outcomes == ["deferred", "admitted"])

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

    @Test("origin loss resolves to terminal unavailable; repository removal separately invalidates facts")
    func originLossResolvesUnavailableAndRepositoryRemovalInvalidatesFacts() async {
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
        // Losing a previously known origin is a terminal "no data is coming"
        // outcome, not a mid-flight invalidation: no automatic query can ever
        // fire again with no origin, so the repo must resolve unavailable
        // rather than fall back to an eternal pending state.
        #expect(await fixture.events.waitForPullRequestsUnavailable(repoId: repoId))
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)
        #expect(await fixture.events.repositoryInvalidationCount(repoId: repoId) == 0)

        await fixture.actor.removeRepository(repo: repoId)
        #expect(await fixture.events.waitForRepositoryInvalidationCount(repoId: repoId, expectedCount: 1))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("a worktree that never resolves an origin terminates as unavailable without ever querying")
    func repositoryWithoutOriginNeverQueriesAndResolvesUnavailable() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.actor.register(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/acme-no-remote"),
            branch: "main"
        )
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
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
        // This is the reported bug: a repo that NEVER had an origin (first
        // encounter, no prior ForgeActor state) must still resolve to
        // unavailable exactly once, not silently stay pending forever.
        #expect(await fixture.events.waitForPullRequestsUnavailable(repoId: repoId))
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)

        fixture.advance(by: .seconds(600))
        await Task.yield()
        #expect(await fixture.provider.callCount == 0)
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)

        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("repeated provider failures resolve to unavailable only after crossing the honesty threshold")
    func repeatedFailuresResolveUnavailableAfterHonestyThreshold() async {
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/unstable")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailureCount(repoId: repoId, expectedCount: 1))
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 0)

        await fixture.clock.waitForPendingSleepCount(atLeast: 1)
        fixture.advance(by: AppPolicies.ForgeRefresh.failureBackoffBaseDelay)
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailureCount(repoId: repoId, expectedCount: 2))
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 0)

        await fixture.clock.waitForPendingSleepCount(atLeast: 1)
        fixture.advance(by: AppPolicies.ForgeRefresh.failureBackoffDelay(forConsecutiveFailureCount: 2))
        #expect(await fixture.provider.waitForCallCount(3))
        await fixture.provider.resolve(callAt: 2, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailureCount(repoId: repoId, expectedCount: 3))
        // Crossing AppPolicies.Forge.consecutiveFailureHonestyThreshold (3) on
        // the 3rd consecutive failure resolves the row to unavailable.
        #expect(await fixture.events.waitForPullRequestsUnavailable(repoId: repoId))
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)

        // Bounded retries keep running at the normal backoff cadence.
        await fixture.clock.waitForPendingSleepCount(atLeast: 1)
        fixture.advance(by: AppPolicies.ForgeRefresh.failureBackoffDelay(forConsecutiveFailureCount: 3))
        #expect(await fixture.provider.waitForCallCount(4))
        let recoveryURL = URL(string: "https://github.com/acme/studio/pull/9")!
        await fixture.provider.resolve(
            callAt: 3,
            with: .complete([
                ForgePullRequest(headRefName: "feature/unstable", url: recoveryURL)
            ])
        )
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/unstable",
                expected: PullRequestFacts(openCount: 1, exactOpenURL: recoveryURL)
            )
        )
        // Exactly one unavailable emission across the whole failure→recovery cycle.
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)

        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("recovery to the same facts after a terminal-unavailable crossing still republishes")
    func equalFactsRecoveryAfterUnavailableStillRepublishesFacts() async {
        // F2: success(N) -> three failures crossing the honesty threshold (which discards the
        // cached facts on RepoCacheAtom's side) -> a retry that resolves to the SAME facts N must
        // still emit .pullRequestsChanged. ForgeActor's own equal-facts suppression compares
        // against its last internally *published* value, which is untouched by the unavailable
        // transition; without resetting that internal baseline when unavailable is emitted, the
        // repeated identical success is wrongly treated as a no-op and the positive PR chip never
        // returns.
        let fixture = await ForgeActorFixture.make()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let pullRequestURL = URL(string: "https://github.com/acme/studio/pull/9")!
        let pullRequest = ForgePullRequest(headRefName: "feature/recover-equal", url: pullRequestURL)

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/recover-equal")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.provider.resolve(callAt: 0, with: .complete([pullRequest]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/recover-equal",
                expected: PullRequestFacts(openCount: 1, exactOpenURL: pullRequestURL)
            )
        )
        #expect(await fixture.events.pullRequestsChangedCount(for: repoId) == 1)

        // From here every retry is driven by an explicit manual refresh() after advancing past its
        // backoff deadline, rather than the clock-driven automatic follow-up: the automatic path
        // additionally gates on AppPolicies.Forge.automaticRefreshMinimumInterval (180s) measured
        // from the ORIGINAL success above, which would swallow these short failure-backoff
        // advances. Manual refresh bypasses that freshness gate and only waits on backoffUntil.
        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailureCount(repoId: repoId, expectedCount: 1))

        fixture.advance(by: AppPolicies.ForgeRefresh.failureBackoffBaseDelay)
        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.waitForCallCount(3))
        await fixture.provider.resolve(callAt: 2, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailureCount(repoId: repoId, expectedCount: 2))

        fixture.advance(by: AppPolicies.ForgeRefresh.failureBackoffDelay(forConsecutiveFailureCount: 2))
        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.waitForCallCount(4))
        await fixture.provider.resolve(callAt: 3, with: .failed(message: "offline"))
        #expect(await fixture.events.waitForRefreshFailureCount(repoId: repoId, expectedCount: 3))
        #expect(await fixture.events.waitForPullRequestsUnavailable(repoId: repoId))
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)

        fixture.advance(by: AppPolicies.ForgeRefresh.failureBackoffDelay(forConsecutiveFailureCount: 3))
        await fixture.actor.refresh(repo: repoId)
        #expect(await fixture.provider.waitForCallCount(5))
        // Same repository, same facts as the original success(N).
        await fixture.provider.resolve(callAt: 4, with: .complete([pullRequest]))

        #expect(
            await fixture.events.waitForPullRequestsChangedCount(repoId: repoId, expectedCount: 2)
        )
        #expect(
            await fixture.events.facts(for: repoId, branch: "feature/recover-equal")
                == PullRequestFacts(openCount: 1, exactOpenURL: pullRequestURL)
        )
        #expect(await fixture.events.pullRequestsUnavailableCount(for: repoId) == 1)

        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }
}

extension ObservedForgeEvents {
    func loadingStates(for repoId: UUID) -> [Bool] {
        recordedEvents.compactMap { event in
            guard case .pullRequestRefreshStateChanged(let eventRepoId, let isLoading) = event,
                eventRepoId == repoId
            else { return nil }
            return isLoading
        }
    }

    func waitForLoadingStates(
        repoId: UUID,
        expected: [Bool],
        maxTurns: Int = 500
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if loadingStates(for: repoId) == expected { return true }
            await Task.yield()
        }
        Issue.record("Expected Forge loading states \(expected), received \(loadingStates(for: repoId))")
        return false
    }

    func pullRequestsUnavailableCount(for repoId: UUID) -> Int {
        recordedEvents.count { event in
            guard case .pullRequestsUnavailable(let eventRepoId) = event else { return false }
            return eventRepoId == repoId
        }
    }

    func waitForPullRequestsUnavailable(repoId: UUID, maxTurns: Int = 500) async -> Bool {
        for _ in 0..<maxTurns {
            if pullRequestsUnavailableCount(for: repoId) > 0 { return true }
            await Task.yield()
        }
        Issue.record("Expected Forge pull requests unavailable for repoId=\(repoId)")
        return false
    }

    func pullRequestsChangedCount(for repoId: UUID) -> Int {
        recordedEvents.count { event in
            guard case .pullRequestsChanged(let eventRepoId, _) = event else { return false }
            return eventRepoId == repoId
        }
    }

    func waitForPullRequestsChangedCount(
        repoId: UUID,
        expectedCount: Int,
        maxTurns: Int = 500
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if pullRequestsChangedCount(for: repoId) == expectedCount { return true }
            await Task.yield()
        }
        Issue.record("Expected \(expectedCount) pullRequestsChanged events for repoId=\(repoId)")
        return false
    }
}

private final class ForgePerformanceRecorderSpy: ForgePerformanceRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedOutcomes: [String] = []

    var outcomes: [String] { lock.withLock { recordedOutcomes } }

    func record(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        attributes: @autoclosure () -> [String: AgentStudioTraceValue]
    ) {
        guard event == .forgeRefresh,
            case .string(let outcome) = attributes()["agentstudio.performance.forge.outcome"]
        else { return }
        lock.withLock { recordedOutcomes.append(outcome) }
    }
}
