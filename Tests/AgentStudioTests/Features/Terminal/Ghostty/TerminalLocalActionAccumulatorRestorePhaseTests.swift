import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

/// SR6b (Program Design item 13): `markRestorePhaseEnded`'s synchronous
/// split, and `beginDrain`'s independent pull of the restore-phase-end
/// alongside (or instead of) ordinary pending work.
@Suite("Terminal local action accumulator restore phase")
struct TerminalLocalActionAccumulatorRestorePhaseTests {
    private let context = TerminalActivityProjectionContext(
        isAttended: false,
        isAgentClassified: false,
        outputBurstThreshold: 30
    )

    @Test("a restore-phase end alone (no other pending work) still schedules and drains")
    func restorePhaseEndAloneStillDrains() throws {
        let recorder = RestorePhaseDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: recorder.record)
        let surfaceID = UUIDv7.generate()
        let generation = RestoreGeneration(rawValue: 1)

        accumulator.markRestorePhaseEnded(surfaceID: surfaceID, generation: generation, contextBeforeControl: context)

        #expect(recorder.requests.count == 1)
        let batch = try #require(accumulator.beginDrain(for: surfaceID, lane: .immediate))
        #expect(batch.restorePhaseEnd?.generation == generation)
        #expect(batch.restorePhaseEnd?.precedingAggregate == nil)
        #expect(batch.activity == nil)
    }

    @Test("the pending aggregate at latch time becomes the preceding aggregate, not later activity")
    func latchSplitsThePrecedingAggregateFromLaterActivity() throws {
        let recorder = RestorePhaseDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: recorder.record)
        let surfaceID = UUIDv7.generate()
        let generation = RestoreGeneration(rawValue: 1)

        // Arrange — output accumulates before the person's first keystroke.
        _ = accumulator.offer(
            .scrollbar(ScrollbarState(top: 0, bottom: 10, total: 40), observedAtMilliseconds: 1000),
            for: surfaceID
        )

        // Act — the latch fires (the input event), then more output arrives
        // before the drain runs.
        accumulator.markRestorePhaseEnded(surfaceID: surfaceID, generation: generation, contextBeforeControl: context)
        _ = accumulator.offer(
            .scrollbar(ScrollbarState(top: 0, bottom: 10, total: 80), observedAtMilliseconds: 1100),
            for: surfaceID
        )
        let batch = try #require(accumulator.beginDrain(for: surfaceID, lane: .immediate))

        // Assert — the pre-input aggregate is on the control; the batch's
        // own `activity` is only what arrived after the latch.
        let precedingAggregate = try #require(batch.restorePhaseEnd?.precedingAggregate)
        #expect(precedingAggregate.aggregate.firstTotalRows == 40)
        #expect(precedingAggregate.aggregate.latestTotalRows == 40)
        let laterActivity = try #require(batch.activity)
        #expect(laterActivity.firstTotalRows == 80)
        #expect(laterActivity.latestTotalRows == 80)
    }

    @Test("a second latch call before the drain runs is a no-op")
    func secondLatchBeforeDrainIsANoOp() throws {
        let recorder = RestorePhaseDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: recorder.record)
        let surfaceID = UUIDv7.generate()
        let firstGeneration = RestoreGeneration(rawValue: 1)
        let secondGeneration = RestoreGeneration(rawValue: 2)

        accumulator.markRestorePhaseEnded(
            surfaceID: surfaceID,
            generation: firstGeneration,
            contextBeforeControl: context
        )
        accumulator.markRestorePhaseEnded(
            surfaceID: surfaceID,
            generation: secondGeneration,
            contextBeforeControl: context
        )

        let batch = try #require(accumulator.beginDrain(for: surfaceID, lane: .immediate))
        #expect(batch.restorePhaseEnd?.generation == firstGeneration)
        #expect(recorder.requests.count == 1)
    }

    @Test("the title lane never carries a restore-phase end")
    func titleLaneNeverCarriesARestorePhaseEnd() throws {
        let recorder = RestorePhaseDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: recorder.record)
        let surfaceID = UUIDv7.generate()
        accumulator.markRestorePhaseEnded(
            surfaceID: surfaceID,
            generation: RestoreGeneration(rawValue: 1),
            contextBeforeControl: context
        )
        _ = accumulator.offer(.titleChanged("A"), for: surfaceID)

        let titleBatch = try #require(accumulator.beginDrain(for: surfaceID, lane: .title))

        #expect(titleBatch.restorePhaseEnd == nil)
    }

    @Test("beginDrain clears the latch so a later drain never redelivers it")
    func beginDrainClearsTheLatch() throws {
        let recorder = RestorePhaseDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: recorder.record)
        let surfaceID = UUIDv7.generate()
        accumulator.markRestorePhaseEnded(
            surfaceID: surfaceID,
            generation: RestoreGeneration(rawValue: 1),
            contextBeforeControl: context
        )
        _ = try #require(accumulator.beginDrain(for: surfaceID, lane: .immediate))
        #expect(accumulator.finishDrain(for: surfaceID, lane: .immediate) == .idle)

        // A later, unrelated offer must not resurrect the already-drained
        // restore-phase end.
        _ = accumulator.offer(
            .scrollbar(ScrollbarState(top: 0, bottom: 10, total: 10), observedAtMilliseconds: 2000),
            for: surfaceID
        )
        let laterBatch = try #require(accumulator.beginDrain(for: surfaceID, lane: .immediate))

        #expect(laterBatch.restorePhaseEnd == nil)
    }
}

private final class RestorePhaseDrainRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(surfaceID: UUID, request: TerminalLocalDrainRequest)] = []

    var requests: [(surfaceID: UUID, request: TerminalLocalDrainRequest)] {
        lock.withLock { storage }
    }

    func record(_ surfaceID: UUID, _ request: TerminalLocalDrainRequest) {
        lock.withLock {
            storage.append((surfaceID: surfaceID, request: request))
        }
    }
}
