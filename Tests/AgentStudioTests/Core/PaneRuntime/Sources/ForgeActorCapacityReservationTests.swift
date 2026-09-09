import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ForgeActor capacity reservation", .serialized)
struct ForgeActorCapacityReservationTests {
    @Test("loading event suspension retains global provider capacity reservation")
    func loadingEventSuspensionRetainsGlobalProviderCapacityReservation() async {
        let emissionGate = ForgeLoadingProjectionEmissionGate()
        let performanceRecorder = ForgeCapacityPerformanceRecorder()
        let fixture = await ForgeActorFixture.make(
            performanceTraceRecorder: performanceRecorder,
            maximumConcurrentProviderRequests: 1,
            beforeEventEmission: { event in
                await emissionGate.pauseFirstLoadingProjection(event)
            }
        )
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        await fixture.register(repoId: firstRepoId, worktrees: [(firstWorktreeId, "feature/first")])
        await fixture.register(repoId: secondRepoId, worktrees: [(secondWorktreeId, "feature/second")])

        let firstDemandTask = Task {
            await fixture.actor.setDemand(worktreeIds: [firstWorktreeId])
        }
        await emissionGate.waitUntilPaused()

        await fixture.actor.setDemand(worktreeIds: [firstWorktreeId, secondWorktreeId])

        #expect(await fixture.provider.callCount == 0)
        #expect(await fixture.events.refreshFailureCount(for: secondRepoId) == 0)
        let deferredSnapshots = performanceRecorder.snapshots
        #expect(deferredSnapshots.reduce(0) { $0 + $1.admission.capacityLimited } == 1)
        #expect(
            deferredSnapshots.contains {
                $0.settlement?.physicalActive == 0
                    && $0.settlement?.pendingActiveFollowUp == 1
                    && $0.settlement?.pendingCapacity == 1
            }
        )
        #expect(deferredSnapshots.reduce(0) { $0 + $1.execution.failed } == 0)

        await emissionGate.resume()
        await firstDemandTask.value
        #expect(await fixture.provider.waitForCallCount(1))
        #expect(await fixture.provider.callCount == 1)

        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(await fixture.provider.waitForCallCount(2))
        #expect(await fixture.provider.maximumActiveCallCount == 1)
        #expect(await fixture.events.refreshFailureCount(for: secondRepoId) == 0)

        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }

    @Test("capacity fallback is consumed until provider completion")
    func capacityFallbackIsConsumedUntilProviderCompletion() async {
        let performanceRecorder = ForgeCapacityPerformanceRecorder()
        let fixture = await ForgeActorFixture.make(
            performanceTraceRecorder: performanceRecorder,
            maximumConcurrentProviderRequests: 1
        )
        let orderedRepoIds = [UUIDv7.generate(), UUIDv7.generate()].sorted {
            $0.uuidString < $1.uuidString
        }
        let firstRepoId = orderedRepoIds[0]
        let secondRepoId = orderedRepoIds[1]
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        await fixture.register(repoId: firstRepoId, worktrees: [(firstWorktreeId, "feature/first")])
        await fixture.register(repoId: secondRepoId, worktrees: [(secondWorktreeId, "feature/second")])

        await fixture.actor.setDemand(worktreeIds: [firstWorktreeId, secondWorktreeId])
        #expect(await fixture.provider.waitForCallCount(1))
        await fixture.clock.waitForPendingSleepCount(exactly: 1)
        let scheduledSleepGeneration = fixture.clock.scheduledSleepGeneration

        let retryDelay = AppPolicies.ForgeRefresh.capacityRecheckDelay
        fixture.advance(by: retryDelay)
        for _ in 0..<1000
        where performanceRecorder.snapshots.reduce(0, { $0 + $1.deadline.fired }) == 0 {
            await Task.yield()
        }

        #expect(performanceRecorder.snapshots.reduce(0) { $0 + $1.deadline.fired } == 1)
        #expect(fixture.clock.scheduledSleepGeneration == scheduledSleepGeneration)
        #expect(fixture.clock.pendingSleepCount == 0)

        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }
}

private final class ForgeCapacityPerformanceRecorder: ForgePerformanceRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSnapshots: [ForgePerformanceSnapshot] = []

    var snapshots: [ForgePerformanceSnapshot] {
        lock.withLock { recordedSnapshots }
    }

    func recordForgePerformanceSnapshot(_ snapshot: ForgePerformanceSnapshot) {
        lock.withLock {
            recordedSnapshots.append(snapshot)
        }
    }
}

private actor ForgeLoadingProjectionEmissionGate {
    private var shouldPause = true
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func pauseFirstLoadingProjection(_ event: ForgeEvent) async {
        guard shouldPause,
            case .pullRequestRepositoryProjectionChanged(_, .loading, _) = event
        else { return }
        shouldPause = false
        isPaused = true
        let waiters = pauseWaiters
        pauseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    func resume() {
        isPaused = false
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
