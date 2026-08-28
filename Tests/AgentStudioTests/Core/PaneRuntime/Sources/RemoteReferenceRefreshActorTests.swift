import AgentStudioGit
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("RemoteReferenceRefreshActor")
struct RemoteReferenceRefreshActorTests {
    @Test("explicit performance outcomes count each terminal attempt and suppress zero")
    func explicitPerformanceOutcomesAreBounded() {
        var accumulator = RemoteReferencePerformanceAccumulator()
        accumulator.increment(\.explicitAdmitted)
        accumulator.increment(\.explicitAdmitted)
        accumulator.recordExplicitSettlement(.completed, count: 2)
        accumulator.recordExplicitSettlement(.failed, count: 1)
        accumulator.recordExplicitSettlement(.obsolete, count: 1)
        accumulator.recordExplicitSettlement(.cancelled, count: 1)
        accumulator.recordExplicitSettlement(.failed, count: 0)

        let snapshot = accumulator.takeSnapshot()
        #expect(snapshot.explicitAdmitted == 2)
        #expect(snapshot.explicitSettledCompleted == 2)
        #expect(snapshot.explicitSettledFailed == 1)
        #expect(snapshot.explicitSettledObsolete == 1)
        #expect(snapshot.explicitSettledCancelled == 1)
    }

    @Test("explicit repository update reports a genuine promotion failure")
    func explicitRepositoryUpdateReportsPromotionFailure() async throws {
        let fixture = RemoteReferenceRefreshFixture(promotionFailuresRemaining: 1)
        let actor = RemoteReferenceRefreshActor(provider: fixture.provider)
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )

        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)

        #expect(await lease.settlement() == .failed)
        await actor.shutdown()
    }

    @Test("explicit repository update remains admitted while remote capacity is occupied")
    func explicitRepositoryUpdateWaitsForCapacity() async throws {
        let fixture = RemoteReferenceRefreshFixture(suspendStaging: true)
        let actor = RemoteReferenceRefreshActor(provider: fixture.provider, maximumConcurrentFetches: 1)
        let secondRepoID = UUIDv7.generate()
        let secondWorktreeID = UUIDv7.generate()
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.register(
            repoId: secondRepoID,
            worktreeId: secondWorktreeID,
            repositoryPath: fixture.repositoryPath.appending(path: "second"),
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await fixture.provider.waitUntilStageSuspended()

        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: secondRepoID,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)
        #expect(await fixture.provider.stageCount == 1)

        await fixture.provider.releaseStage()
        await fixture.provider.waitForStageCount(2)
        await fixture.provider.waitUntilStageSuspended()
        await fixture.provider.releaseStage()
        #expect(await lease.settlement() == .completed)
        await actor.shutdown()
    }

    @Test("explicit repository update without remote registration is not applicable")
    func explicitRepositoryUpdateWithoutRegistrationIsNotApplicable() async {
        let actor = RemoteReferenceRefreshActor()

        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: UUIDv7.generate(),
            attemptId: UUIDv7.generate()
        )

        #expect(admission.acceptedLease == nil)
        await actor.shutdown()
    }

    @Test("cold explicit repository update remains admitted through remote child settlement")
    func coldExplicitRepositoryUpdateWaitsForPhysicalSettlement() async throws {
        let fixture = RemoteReferenceRefreshFixture(suspendStaging: true)
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )

        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)
        await fixture.provider.waitUntilStageSuspended()
        let admissionPerformance = performanceRecorder.combinedSnapshot
        #expect(admissionPerformance.explicitAdmitted == 1)
        #expect(admissionPerformance.explicitSettledCompleted == 0)
        #expect(admissionPerformance.automaticWithoutDemandStarted == 0)

        await fixture.provider.releaseStage()
        #expect(await lease.settlement() == .completed)
        await actor.waitUntilIdle()
        #expect(await fixture.provider.promoteCount == 1)
        let settlementPerformance = performanceRecorder.combinedSnapshot
        #expect(settlementPerformance.explicitAdmitted == 1)
        #expect(settlementPerformance.explicitSettledCompleted == 1)
        #expect(settlementPerformance.automaticWithoutDemandStarted == 0)

        await actor.shutdown()
    }

    @Test("current demanded stage promotes and targets represented worktrees")
    func currentDemandPromotesAndRecomputes() async throws {
        let fixture = RemoteReferenceRefreshFixture()
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        #expect(await fixture.acceptanceRecorder.localInstallationCount == 1)
        #expect(await fixture.acceptanceRecorder.acceptanceCount == 0)
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()

        #expect(await fixture.provider.stageCount == 1)
        #expect(await fixture.provider.promoteCount == 1)
        #expect(await fixture.provider.cleanupCount == 1)
        let accepted = try #require(await fixture.acceptanceRecorder.lastAcceptance)
        #expect(accepted.repoId == fixture.repoId)
        #expect(accepted.expectedOrigin == fixture.originA)
        #expect(await fixture.acceptanceRecorder.lastWorktreeIds == [fixture.worktreeId])
        #expect(await fixture.acceptanceRecorder.acceptanceCount == 1)
        let performance = performanceRecorder.combinedSnapshot
        #expect(performance.demandChanged == 1)
        #expect(performance.admissionAdmitted == 1)
        #expect(performance.stagingStarted == 1)
        #expect(performance.stagingCompleted == 1)
        #expect(performance.promotionStarted == 1)
        #expect(performance.promotionCompleted == 1)
        #expect(performance.publicationLocalAccepted == 1)
        #expect(performance.publicationPromoted == 1)
        #expect(performance.cleanupSucceeded == 1)
        #expect(performanceRecorder.settlements.contains { $0.physicalActive == 1 })
        #expect(performanceRecorder.settlements.last?.physicalActive == 0)

        await actor.shutdown()
    }

    @Test("equal registration performs no provider work or acceptance callback")
    func equalRegistrationIsSuppressedBeforeProviderCapture() async {
        let fixture = RemoteReferenceRefreshFixture()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let captureCount = await fixture.provider.captureCount
        let cleanupAbandonedCount = await fixture.provider.cleanupAbandonedCount
        let acceptanceCount = await fixture.acceptanceRecorder.acceptanceCount

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )

        #expect(await fixture.provider.captureCount == captureCount)
        #expect(await fixture.provider.cleanupAbandonedCount == cleanupAbandonedCount)
        #expect(await fixture.acceptanceRecorder.acceptanceCount == acceptanceCount)
        await actor.shutdown()
    }

    @Test("topology replacement captures local authority once per changed repository")
    func topologyReplacementCapturesOncePerChangedRepository() async {
        let fixture = RemoteReferenceRefreshFixture()
        let secondWorktreeId = UUIDv7.generate()
        let actor = RemoteReferenceRefreshActor(provider: fixture.provider)

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let captureCountBeforeReplacement = await fixture.provider.captureCount

        await actor.assertTopology([
            fixture.worktreeId: WorktreeFilesystemContext(
                repoId: fixture.repoId,
                rootPath: fixture.repositoryPath
            ),
            secondWorktreeId: WorktreeFilesystemContext(
                repoId: fixture.repoId,
                rootPath: fixture.repositoryPath.appending(path: "second-worktree")
            ),
        ])

        #expect(await fixture.provider.captureCount == captureCountBeforeReplacement + 1)
        let captureCountAfterReplacement = await fixture.provider.captureCount
        await actor.assertTopology([
            secondWorktreeId: WorktreeFilesystemContext(
                repoId: fixture.repoId,
                rootPath: fixture.repositoryPath.appending(path: "second-worktree")
            ),
            fixture.worktreeId: WorktreeFilesystemContext(
                repoId: fixture.repoId,
                rootPath: fixture.repositoryPath
            ),
        ])
        #expect(await fixture.provider.captureCount == captureCountAfterReplacement)
        await actor.shutdown()
    }

    @Test("cleanup failure retries independently without reopening source work")
    func cleanupFailureRetriesWithoutSourceBackoff() async {
        let fixture = RemoteReferenceRefreshFixture(cleanupFailuresRemaining: 1)
        let clock = TestPushClock()
        let monotonicNow = RemoteReferenceMonotonicNow()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            monotonicNow: { monotonicNow.value },
            sleepClock: clock,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()

        #expect(await fixture.provider.stageCount == 1)
        #expect(await fixture.provider.cleanupCount == 1)
        #expect(await fixture.acceptanceRecorder.acceptanceCount == 1)

        let retryDelay = AppPolicies.RemoteReferenceRefresh.capacityRecheckDelay
        await clock.waitForPendingSleepCount(atLeast: 1)
        monotonicNow.advance(by: retryDelay)
        clock.advance(by: retryDelay)
        await fixture.provider.waitForCleanupCount(2)

        #expect(await fixture.provider.stageCount == 1)
        #expect(await fixture.provider.cleanupCount == 2)
        await actor.shutdown()
    }

    @Test("final unregister retains failed cleanup custody until retry succeeds")
    func finalUnregisterRetainsCleanupDebt() async {
        let fixture = RemoteReferenceRefreshFixture(cleanupFailuresRemaining: 1)
        let clock = TestPushClock()
        let monotonicNow = RemoteReferenceMonotonicNow()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            monotonicNow: { monotonicNow.value },
            sleepClock: clock
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()
        #expect(await fixture.provider.cleanupCount == 1)

        await actor.unregister(worktreeId: fixture.worktreeId, repoId: fixture.repoId)
        let retryDelay = AppPolicies.RemoteReferenceRefresh.capacityRecheckDelay
        await clock.waitForPendingSleepCount(atLeast: 1)
        monotonicNow.advance(by: retryDelay)
        clock.advance(by: retryDelay)
        await fixture.provider.waitForCleanupCount(2)

        #expect(await fixture.provider.cleanupCount == 2)
        await actor.shutdown()
    }

    @Test("genuine promotion failure retries only at the source failure floor")
    func genuineFailureUsesSourceBackoff() async {
        let fixture = RemoteReferenceRefreshFixture(promotionFailuresRemaining: 1)
        let clock = TestPushClock()
        let monotonicNow = RemoteReferenceMonotonicNow()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            monotonicNow: { monotonicNow.value },
            sleepClock: clock
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 1)

        let retryFloor = AppPolicies.RemoteReferenceRefresh.automaticFailureRetryFloor
        let beforeRetryFloor = retryFloor - .seconds(1)
        await clock.waitForPendingSleepCount(atLeast: 1)
        monotonicNow.advance(by: beforeRetryFloor)
        clock.advance(by: beforeRetryFloor)
        #expect(await fixture.provider.stageCount == 1)

        monotonicNow.advance(by: .seconds(1))
        clock.advance(by: .seconds(1))
        await fixture.provider.waitForStageCount(2)
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 2)
        await actor.shutdown()
    }

    @Test("origin change during staged fetch cleans without promotion")
    func staleOriginCannotPromote() async {
        let fixture = RemoteReferenceRefreshFixture(suspendStaging: true)
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let acceptanceCountBeforeFetch = await fixture.acceptanceRecorder.acceptanceCount
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await fixture.provider.waitUntilStageStarted()
        await fixture.provider.waitUntilStageSuspended()

        let originChangeTask = Task {
            await actor.setOrigin(repoId: fixture.repoId, expectedOrigin: fixture.originB)
        }
        await fixture.provider.releaseStage()
        await originChangeTask.value
        await actor.waitUntilIdle()

        #expect(await fixture.provider.promoteCount == 0)
        #expect(await fixture.provider.cleanupCount == 1)
        #expect(await fixture.acceptanceRecorder.acceptanceCount == acceptanceCountBeforeFetch)

        await actor.shutdown()
    }

    @Test("no demand performs no staged fetch")
    func noDemandPerformsNoStagedFetch() async {
        let fixture = RemoteReferenceRefreshFixture()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { _ in }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.waitUntilIdle()

        #expect(await fixture.provider.stageCount == 0)
        await actor.shutdown()
    }

    @Test("origin change revokes a suspended promotion before canonical mutation")
    func originChangeRevokesSuspendedPromotion() async {
        let fixture = RemoteReferenceRefreshFixture(suspendPromotion: true)
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let acceptanceCountBeforeFetch = await fixture.acceptanceRecorder.acceptanceCount
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await fixture.provider.waitUntilPromotionSuspended()

        let originChangeTask = Task {
            await actor.setOrigin(repoId: fixture.repoId, expectedOrigin: fixture.originB)
        }
        await fixture.provider.waitForCleanupCount(1)
        await fixture.provider.releasePromotion()
        await originChangeTask.value
        await actor.waitUntilIdle()

        #expect(await fixture.provider.promotionMutationCount == 0)
        #expect(await fixture.acceptanceRecorder.acceptanceCount == acceptanceCountBeforeFetch)
        await actor.shutdown()
    }

    @Test("fresh automatic demand is suppressed while explicit refresh bypasses freshness")
    func freshnessAndExplicitRefreshAdmission() async {
        let fixture = RemoteReferenceRefreshFixture()
        let actor = RemoteReferenceRefreshActor(provider: fixture.provider)

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 1)

        await actor.setDemand(repositoryIds: [])
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 1)

        await actor.refresh(repoId: fixture.repoId)
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 2)
        await actor.shutdown()
    }

    @Test("demand loss cleans staged work without promotion")
    func demandLossCleansWithoutPromotion() async {
        let fixture = RemoteReferenceRefreshFixture(suspendStaging: true)
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await fixture.provider.waitUntilStageSuspended()

        let demandLossTask = Task { await actor.setDemand(repositoryIds: []) }
        await fixture.provider.releaseStage()
        await demandLossTask.value
        await actor.waitUntilIdle()

        #expect(await fixture.provider.promoteCount == 0)
        #expect(await fixture.provider.cleanupCount == 1)
        #expect(await fixture.acceptanceRecorder.localInstallationCount == 1)
        #expect(await fixture.acceptanceRecorder.invalidationCount == 0)
        await actor.shutdown()
    }

    @Test("automatic refresh becomes eligible exactly at the freshness deadline")
    func automaticRefreshUsesFreshnessDeadline() async {
        let fixture = RemoteReferenceRefreshFixture()
        let clock = TestPushClock()
        let monotonicNow = RemoteReferenceMonotonicNow()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            monotonicNow: { monotonicNow.value },
            sleepClock: clock,
            onAuthorityUpdate: { _ in }
        )

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 1)

        monotonicNow.advance(by: .seconds(179))
        clock.advance(by: .seconds(179))
        #expect(await fixture.provider.stageCount == 1)

        monotonicNow.advance(by: .seconds(1))
        clock.advance(by: .seconds(1))
        await fixture.provider.waitForStageCount(2)
        await actor.waitUntilIdle()
        #expect(await fixture.provider.stageCount == 2)
        await actor.shutdown()
    }

    @Test("process capacity one defers a second demanded repository without a second start")
    func capacityOneDefersSecondRepository() async {
        let fixture = RemoteReferenceRefreshFixture(suspendStaging: true)
        let actor = RemoteReferenceRefreshActor(provider: fixture.provider)
        let secondRepoId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()

        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.register(
            repoId: secondRepoId,
            worktreeId: secondWorktreeId,
            repositoryPath: fixture.repositoryPath.appending(path: "second"),
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId, secondRepoId])
        await fixture.provider.waitUntilStageSuspended()
        #expect(await fixture.provider.stageCount == 1)

        let demandLossTask = Task { await actor.setDemand(repositoryIds: []) }
        await fixture.provider.releaseStage()
        await demandLossTask.value
        await actor.waitUntilIdle()

        #expect(await fixture.provider.stageCount == 1)
        await actor.shutdown()
    }

    @Test("expired currentness retry is consumed while fetch capacity remains occupied")
    func expiredCurrentnessRetryIsConsumedWhileCapacityRemainsOccupied() async {
        let fixture = RemoteReferenceRefreshFixture(suspendStaging: true)
        let clock = TestPushClock()
        let monotonicNow = RemoteReferenceMonotonicNow()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            maximumConcurrentFetches: 1,
            monotonicNow: { monotonicNow.value },
            sleepClock: clock
        )
        let orderedRepoIds = [UUIDv7.generate(), UUIDv7.generate()].sorted {
            $0.uuidString < $1.uuidString
        }
        let obsoleteRepoId = orderedRepoIds[0]
        let capacityRepoId = orderedRepoIds[1]
        let obsoleteWorktreeId = UUIDv7.generate()
        let capacityWorktreeId = UUIDv7.generate()

        await actor.register(
            repoId: obsoleteRepoId,
            worktreeId: obsoleteWorktreeId,
            repositoryPath: fixture.repositoryPath.appending(path: "obsolete"),
            remoteName: "origin",
            expectedOrigin: fixture.originB
        )
        await actor.register(
            repoId: capacityRepoId,
            worktreeId: capacityWorktreeId,
            repositoryPath: fixture.repositoryPath.appending(path: "capacity"),
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [obsoleteRepoId, capacityRepoId])
        await fixture.provider.waitUntilStageSuspended()
        await clock.waitForPendingSleepCount(exactly: 1)
        let scheduledSleepGeneration = clock.scheduledSleepGeneration

        let retryDelay = AppPolicies.RemoteReferenceRefresh.capacityRecheckDelay
        monotonicNow.advance(by: retryDelay)
        clock.advance(by: retryDelay)
        for _ in 0..<1000 where clock.scheduledSleepGeneration == scheduledSleepGeneration {
            await Task.yield()
        }

        #expect(clock.scheduledSleepGeneration == scheduledSleepGeneration)
        #expect(clock.pendingSleepCount == 0)

        await fixture.provider.releaseStage()
        await actor.waitUntilIdle()
        await actor.shutdown()
    }
}

private final class RemoteReferencePerformanceRecorderSpy:
    RemoteReferencePerformanceRecording, @unchecked Sendable
{
    private let lock = NSLock()
    private var snapshots: [RemoteReferencePerformanceSnapshot] = []

    var combinedSnapshot: RemoteReferencePerformanceSnapshot {
        lock.withLock {
            snapshots.reduce(into: RemoteReferencePerformanceSnapshot()) { result, snapshot in
                result.demandChanged += snapshot.demandChanged
                result.demandCleared += snapshot.demandCleared
                result.admissionAdmitted += snapshot.admissionAdmitted
                result.admissionCapacityDeferred += snapshot.admissionCapacityDeferred
                result.stagingStarted += snapshot.stagingStarted
                result.automaticWithoutDemandStarted += snapshot.automaticWithoutDemandStarted
                result.explicitAdmitted += snapshot.explicitAdmitted
                result.explicitSettledCompleted += snapshot.explicitSettledCompleted
                result.explicitSettledFailed += snapshot.explicitSettledFailed
                result.explicitSettledObsolete += snapshot.explicitSettledObsolete
                result.explicitSettledCancelled += snapshot.explicitSettledCancelled
                result.stagingCompleted += snapshot.stagingCompleted
                result.promotionStarted += snapshot.promotionStarted
                result.promotionCompleted += snapshot.promotionCompleted
                result.executionFailed += snapshot.executionFailed
                result.executionCancelled += snapshot.executionCancelled
                result.validationCurrent += snapshot.validationCurrent
                result.validationObsolete += snapshot.validationObsolete
                result.publicationLocalAccepted += snapshot.publicationLocalAccepted
                result.publicationPromoted += snapshot.publicationPromoted
                result.publicationInvalidated += snapshot.publicationInvalidated
                result.cleanupSucceeded += snapshot.cleanupSucceeded
                result.cleanupFailed += snapshot.cleanupFailed
            }
        }
    }

    var settlements: [RemoteReferencePerformanceSnapshot.Settlement] {
        lock.withLock { snapshots.compactMap(\.settlement) }
    }

    func recordRemoteReferencePerformanceSnapshot(_ snapshot: RemoteReferencePerformanceSnapshot) {
        lock.withLock { snapshots.append(snapshot) }
    }
}

private struct RemoteReferenceRefreshFixture {
    let repoId = UUIDv7.generate()
    let worktreeId = UUIDv7.generate()
    let repositoryPath = URL(filePath: "/tmp/remote-reference-refresh", directoryHint: .isDirectory)
    let originA = "https://example.com/owner/repository-a.git"
    let originB = "https://example.com/owner/repository-b.git"
    let provider: RemoteReferenceRefreshProviderFake
    let acceptanceRecorder = RemoteReferenceAcceptanceRecorder()

    init(
        suspendStaging: Bool = false,
        suspendPromotion: Bool = false,
        cleanupFailuresRemaining: Int = 0,
        promotionFailuresRemaining: Int = 0
    ) {
        provider = RemoteReferenceRefreshProviderFake(
            suspendStaging: suspendStaging,
            suspendPromotion: suspendPromotion,
            cleanupFailuresRemaining: cleanupFailuresRemaining,
            promotionFailuresRemaining: promotionFailuresRemaining
        )
    }
}

private actor RemoteReferenceAcceptanceRecorder {
    private(set) var lastAcceptance: RemoteReferenceAcceptance?
    private(set) var lastWorktreeIds: Set<UUID> = []
    private(set) var acceptanceCount = 0
    private(set) var localInstallationCount = 0
    private(set) var invalidationCount = 0

    func record(_ update: RemoteReferenceAuthorityUpdate) {
        switch update {
        case .invalidated:
            invalidationCount += 1
        case .localAccepted:
            localInstallationCount += 1
        case .promoted(let acceptance, let worktreeIds):
            lastAcceptance = acceptance
            lastWorktreeIds = worktreeIds
            acceptanceCount += 1
        }
    }
}

private actor RemoteReferenceRefreshProviderFake: RemoteReferenceRefreshProviding {
    private enum FakeError: Error {
        case cleanupFailed
        case promotionFailed
        case promotionRevoked
    }

    private let suspendStaging: Bool
    private let suspendPromotion: Bool
    private var cleanupFailuresRemaining: Int
    private var promotionFailuresRemaining: Int
    private var stageStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var stageSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var promotionSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var cleanupCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var stageCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var stageContinuation: CheckedContinuation<Void, Never>?
    private var promotionContinuation: CheckedContinuation<Void, Never>?
    private var promotionWasRevoked = false
    private(set) var captureCount = 0
    private(set) var stageCount = 0
    private(set) var promoteCount = 0
    private(set) var cleanupCount = 0
    private(set) var cleanupAbandonedCount = 0
    private(set) var promotionMutationCount = 0

    init(
        suspendStaging: Bool,
        suspendPromotion: Bool,
        cleanupFailuresRemaining: Int,
        promotionFailuresRemaining: Int
    ) {
        self.suspendStaging = suspendStaging
        self.suspendPromotion = suspendPromotion
        self.cleanupFailuresRemaining = cleanupFailuresRemaining
        self.promotionFailuresRemaining = promotionFailuresRemaining
    }

    func captureRemoteTrackingSnapshot(
        repositoryPath: URL,
        remoteName: String
    ) async throws -> GitRemoteTrackingSnapshot {
        captureCount += 1
        return GitRemoteTrackingSnapshot(
            repositoryPath: repositoryPath,
            repositoryCommonDirectory: repositoryPath.appending(path: ".git"),
            remoteName: remoteName,
            configuredRemoteURL: "https://example.com/owner/repository-a.git",
            effectiveFetchURL: "https://example.com/owner/repository-a.git",
            references: []
        )
    }

    func stageFetch(snapshot: GitRemoteTrackingSnapshot, stagingId: UUID) async throws -> GitStagedFetchResult {
        stageCount += 1
        promotionWasRevoked = false
        let readyStageCountWaiters = stageCountWaiters.filter { $0.count <= stageCount }
        stageCountWaiters.removeAll { $0.count <= stageCount }
        for waiter in readyStageCountWaiters { waiter.continuation.resume() }
        let waiters = stageStartedWaiters
        stageStartedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if suspendStaging {
            await withCheckedContinuation { continuation in
                stageContinuation = continuation
                let waiters = stageSuspensionWaiters
                stageSuspensionWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        return GitStagedFetchResult(
            snapshot: snapshot,
            handle: GitStagedFetchHandle(
                repositoryCommonDirectory: snapshot.repositoryCommonDirectory,
                stagingID: stagingId
            ),
            promotionGuard: nil,
            updates: [],
            verifications: [],
            deletions: []
        )
    }

    func promoteStagedFetch(_: GitStagedFetchResult) async throws {
        promoteCount += 1
        if suspendPromotion {
            await withCheckedContinuation { continuation in
                promotionContinuation = continuation
                let waiters = promotionSuspensionWaiters
                promotionSuspensionWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        guard !promotionWasRevoked else { throw FakeError.promotionRevoked }
        if promotionFailuresRemaining > 0 {
            promotionFailuresRemaining -= 1
            throw FakeError.promotionFailed
        }
        promotionMutationCount += 1
    }

    func cleanupStagedFetch(_: GitStagedFetchHandle) async throws {
        cleanupCount += 1
        promotionWasRevoked = true
        let readyWaiters = cleanupCountWaiters.filter { $0.count <= cleanupCount }
        cleanupCountWaiters.removeAll { $0.count <= cleanupCount }
        for waiter in readyWaiters { waiter.continuation.resume() }
        if cleanupFailuresRemaining > 0 {
            cleanupFailuresRemaining -= 1
            throw FakeError.cleanupFailed
        }
    }

    func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory _: URL,
        retainedStagingIds _: Set<UUID>
    ) async {
        cleanupAbandonedCount += 1
    }

    func waitUntilStageStarted() async {
        guard stageCount == 0 else { return }
        await withCheckedContinuation { continuation in
            stageStartedWaiters.append(continuation)
        }
    }

    func releaseStage() {
        stageContinuation?.resume()
        stageContinuation = nil
    }

    func waitUntilStageSuspended() async {
        guard stageContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            stageSuspensionWaiters.append(continuation)
        }
    }

    func waitUntilPromotionSuspended() async {
        guard promotionContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            promotionSuspensionWaiters.append(continuation)
        }
    }

    func releasePromotion() {
        promotionContinuation?.resume()
        promotionContinuation = nil
    }

    func waitForCleanupCount(_ count: Int) async {
        guard cleanupCount < count else { return }
        await withCheckedContinuation { continuation in
            cleanupCountWaiters.append((count, continuation))
        }
    }

    func waitForStageCount(_ count: Int) async {
        guard stageCount < count else { return }
        await withCheckedContinuation { continuation in
            stageCountWaiters.append((count, continuation))
        }
    }
}

private final class RemoteReferenceMonotonicNow: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed = Duration.zero

    var value: Duration { lock.withLock { elapsed } }

    func advance(by duration: Duration) {
        lock.withLock { elapsed += duration }
    }
}
