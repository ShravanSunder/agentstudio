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

        let snapshot = accumulator.takeSnapshot()

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
        #expect(!snapshot.isEmpty)
        #expect(accumulator.takeSnapshot().isEmpty)
    }

    @Test("ForgeActor accumulates inputs without recorder fanout and flushes once per provider completion")
    func actorFlushesOneAggregateSnapshotPerProviderCompletion() async throws {
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
        let snapshot = try #require(recorder.snapshots.only)

        #expect(snapshot.inputs.automatic >= 1)
        #expect(snapshot.inputs.manual == 2)
        #expect(snapshot.admission.admitted == 2)
        #expect(snapshot.admission.activeRequestCoalesced == 2)
        #expect(snapshot.admission.capacityLimited == 0)
        #expect(snapshot.execution.started == 2)
        #expect(snapshot.execution.completed == 1)
        #expect(snapshot.validation.current == 1)
        #expect(snapshot.publication.published >= 2)

        await fixture.actor.flushPerformanceSnapshot()
        #expect(recorder.snapshots.count == 1)

        await fixture.provider.resolve(callAt: 1, with: .complete([]))
        await fixture.actor.shutdown()
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

extension Array {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}
