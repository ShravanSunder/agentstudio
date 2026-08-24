import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Forge performance accumulator", .serialized)
struct ForgePerformanceAccumulatorTests {
    @Test("fixed outcome counters snapshot and reset without retaining input identity")
    func fixedOutcomeCountersSnapshotAndReset() {
        var accumulator = ForgePerformanceAccumulator()

        accumulator.recordInput(.automatic)
        accumulator.recordInput(.manual)
        accumulator.recordInput(.followUp)
        accumulator.recordAdmission(.admitted)
        accumulator.recordAdmission(.activeRequestCoalesced)
        accumulator.recordAdmission(.capacityLimited)
        accumulator.recordExecution(.started)
        accumulator.recordExecution(.completed)
        accumulator.recordValidation(.current)
        accumulator.recordPublication(.published)
        accumulator.recordDeadline(.scheduled)
        accumulator.recordDeadline(.fired)
        accumulator.recordQueryPlan(demandedBranchCount: 3, aliasBatchCount: 1)
        accumulator.recordQueryOutcome(
            .complete([
                ForgePullRequest(
                    headRefName: "main",
                    url: URL(string: "https://example.test/pull/1")!
                )
            ])
        )
        accumulator.recordUnavailableTransition()
        accumulator.recordRecovery()
        accumulator.recordPhysicalState(active: 2, pending: 4)

        let settlement = ForgePerformanceSnapshot.Settlement(
            physicalActive: 2,
            pendingTotal: 4,
            pendingFuture: 1,
            pendingReady: 1,
            pendingCapacity: 1,
            pendingActiveFollowUp: 1,
            pendingUnclassified: 0,
            deadlineOverdue: 0,
            deadlineNextMilliseconds: 1000
        )

        let snapshot = accumulator.takeSnapshot(settlement: settlement)

        #expect(snapshot.inputs.automatic == 1)
        #expect(snapshot.inputs.manual == 1)
        #expect(snapshot.inputs.followUp == 1)
        #expect(snapshot.admission.admitted == 1)
        #expect(snapshot.admission.activeRequestCoalesced == 1)
        #expect(snapshot.admission.capacityLimited == 1)
        #expect(snapshot.execution.started == 1)
        #expect(snapshot.execution.completed == 1)
        #expect(snapshot.validation.current == 1)
        #expect(snapshot.publication.published == 1)
        #expect(snapshot.deadline.scheduled == 1)
        #expect(snapshot.deadline.fired == 1)
        #expect(snapshot.query.demandedBranchCount == 3)
        #expect(snapshot.query.aliasBatchCount == 1)
        #expect(snapshot.query.returnedNodeCount == 1)
        #expect(snapshot.query.completePlan == 1)
        #expect(snapshot.recovery.unavailable == 1)
        #expect(snapshot.recovery.recovered == 1)
        #expect(snapshot.physical.activeMaximum == 2)
        #expect(snapshot.physical.pendingMaximum == 4)
        #expect(snapshot.settlement == settlement)
        #expect(!snapshot.isEmpty)
        #expect(accumulator.takeSnapshot().isEmpty)

        let settledZero = ForgePerformanceSnapshot.Settlement(
            physicalActive: 0,
            pendingTotal: 0,
            pendingFuture: 0,
            pendingReady: 0,
            pendingCapacity: 0,
            pendingActiveFollowUp: 0,
            pendingUnclassified: 0,
            deadlineOverdue: 0,
            deadlineNextMilliseconds: 0
        )
        #expect(!accumulator.takeSnapshot(settlement: settledZero).isEmpty)
    }

    @Test("ForgeActor emits current physical state while retaining bounded aggregate counters")
    func actorEmitsCurrentPhysicalStateAndAggregateCounters() async throws {
        let recorder = ForgePerformanceSnapshotRecorderSpy()
        let fixture = await ForgeActorFixture.make(performanceTraceRecorder: recorder)
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await fixture.register(repoId: repoId, worktrees: [(worktreeId, "feature/telemetry")])
        await fixture.actor.setDemand(worktreeIds: [worktreeId])
        #expect(await fixture.provider.waitForCallCount(1))

        await fixture.actor.refresh(repo: repoId)
        await fixture.actor.refresh(repo: repoId)

        await fixture.provider.resolve(callAt: 0, with: .complete([]))
        #expect(
            await fixture.events.waitForFacts(
                repoId: repoId,
                branch: "feature/telemetry",
                expected: PullRequestFacts(openCount: 0, exactOpenURL: nil)
            )
        )
        #expect(await fixture.provider.waitForCallCount(2))
        await fixture.actor.flushPerformanceSnapshot()
        let snapshots = recorder.snapshots

        #expect(snapshots.reduce(0) { $0 + $1.inputs.automatic } >= 1)
        #expect(snapshots.reduce(0) { $0 + $1.inputs.manual } == 2)
        #expect(snapshots.reduce(0) { $0 + $1.admission.admitted } == 2)
        #expect(snapshots.reduce(0) { $0 + $1.admission.activeRequestCoalesced } == 2)
        #expect(snapshots.reduce(0) { $0 + $1.admission.capacityLimited } == 0)
        #expect(snapshots.reduce(0) { $0 + $1.execution.started } == 2)
        #expect(snapshots.reduce(0) { $0 + $1.execution.completed } == 1)
        #expect(snapshots.reduce(0) { $0 + $1.validation.current } == 1)
        #expect(snapshots.reduce(0) { $0 + $1.publication.published } >= 2)
        #expect(snapshots.contains { $0.settlement?.physicalActive == 1 })
        #expect(snapshots.contains { $0.physical.activeMaximum >= 1 })

        let snapshotCountAfterExplicitFlush = recorder.snapshots.count
        await fixture.actor.flushPerformanceSnapshot()
        #expect(recorder.snapshots.count == snapshotCountAfterExplicitFlush)

        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
        #expect(recorder.snapshots.last?.settlement?.physicalActive == 0)
        #expect(recorder.snapshots.last?.settlement?.pendingTotal == 0)
        await fixture.stopObserving()
    }
}

private final class ForgePerformanceSnapshotRecorderSpy: ForgePerformanceRecording, @unchecked Sendable {
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
