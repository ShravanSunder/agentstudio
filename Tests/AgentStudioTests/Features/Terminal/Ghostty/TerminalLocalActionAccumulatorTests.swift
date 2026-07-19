import Foundation
import Testing

@testable import AgentStudio

@Suite("Terminal local action accumulator")
struct TerminalLocalActionAccumulatorTests {
    @Test("one hundred thousand samples retain fixed state and preserve sufficient statistics")
    func largeBurstIsBounded() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceIDs = (0..<10).map { _ in UUIDv7.generate() }

        for sampleIndex in 0..<100_000 {
            let surfaceIndex = sampleIndex % surfaceIDs.count
            let perSurfaceIndex = sampleIndex / surfaceIDs.count
            let total = 1000 + perSurfaceIndex
            accumulator.offer(
                .scrollbar(
                    ScrollbarState(top: total - 20, bottom: total, total: total),
                    observedAtMilliseconds: Int64(sampleIndex)
                ),
                for: surfaceIDs[surfaceIndex]
            )
            accumulator.offer(.mouseVisibility(sampleIndex.isMultiple(of: 2)), for: surfaceIDs[surfaceIndex])
        }

        #expect(scheduler.scheduledSurfaceIDs.count == surfaceIDs.count)
        #expect(accumulator.pendingSurfaceCount == surfaceIDs.count)
        #expect(
            accumulator.retainedEntryCount <= surfaceIDs.count
                * TerminalLocalActionAccumulator.maximumRetainedEntriesPerSurface)

        for (surfaceIndex, surfaceID) in surfaceIDs.enumerated() {
            let batch = try #require(accumulator.beginDrain(for: surfaceID))
            let expectedLatestTotal = 1000 + ((99_990 + surfaceIndex) / surfaceIDs.count)
            #expect(batch.presentation.scrollbarState?.total == expectedLatestTotal)
            #expect(batch.activity?.sampleCount == 10_000)
            #expect(batch.activity?.cumulativePositiveRowGrowth == 9999)
            #expect(batch.activity?.firstTotalRows == 1000)
            #expect(batch.activity?.latestTotalRows == expectedLatestTotal)
            #expect(accumulator.finishDrain(for: surfaceID) == .idle)
        }

        #expect(accumulator.pendingSurfaceCount == 0)
        #expect(accumulator.retainedEntryCount == 0)
    }

    @Test("growth before decreases and pinned edges survive coalescing")
    func sufficientStatisticsSurviveReset() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()
        let samples = [
            ScrollbarState(top: 90, bottom: 100, total: 100),
            ScrollbarState(top: 100, bottom: 110, total: 110),
            ScrollbarState(top: 50, bottom: 60, total: 100),
            ScrollbarState(top: 95, bottom: 105, total: 105),
        ]

        for (index, state) in samples.enumerated() {
            accumulator.offer(.scrollbar(state, observedAtMilliseconds: Int64(index + 10)), for: surfaceID)
        }

        let batch = try #require(accumulator.beginDrain(for: surfaceID))
        let activity = try #require(batch.activity)
        #expect(activity.cumulativePositiveRowGrowth == 15)
        #expect(activity.firstObservedAtMilliseconds == 10)
        #expect(activity.latestObservedAtMilliseconds == 13)
        #expect(activity.didExitPinnedToBottom)
        #expect(activity.didEnterPinnedToBottom)
        #expect(activity.latestIsPinnedToBottom)
    }

    @Test("offers during a drain create exactly one convergent follow-up")
    func oneFollowUpDrain() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        accumulator.offer(.mouseShape(.text), for: surfaceID)
        _ = try #require(accumulator.beginDrain(for: surfaceID))
        accumulator.offer(.mouseShape(.pointer), for: surfaceID)
        accumulator.offer(.mouseVisibility(false), for: surfaceID)

        #expect(scheduler.scheduledSurfaceIDs == [surfaceID])
        #expect(accumulator.finishDrain(for: surfaceID) == .followUpScheduled)
        #expect(scheduler.scheduledSurfaceIDs == [surfaceID, surfaceID])

        let followUp = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(followUp.presentation.mouseShape == .pointer)
        #expect(followUp.presentation.mouseVisibility == false)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
        #expect(scheduler.scheduledSurfaceIDs == [surfaceID, surfaceID])
    }

    @Test("search lifecycle barriers reject late values after end")
    func searchBarrierRejectsLateValues() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        #expect(accumulator.offer(.searchStarted(query: "needle"), for: surfaceID) == .scheduled)
        #expect(accumulator.offer(.searchMatches(7), for: surfaceID) == .coalesced)
        #expect(accumulator.offer(.searchSelection(2), for: surfaceID) == .coalesced)
        #expect(accumulator.offer(.searchEnded, for: surfaceID) == .coalesced)
        #expect(accumulator.offer(.searchMatches(99), for: surfaceID) == .rejectedInactiveSearch)
        #expect(accumulator.offer(.searchSelection(98), for: surfaceID) == .rejectedInactiveSearch)

        let batch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(batch.searchLifecycle?.firstEpoch == 1)
        #expect(batch.searchLifecycle?.latestEpoch == 1)
        #expect(batch.searchLifecycle?.transitionCount == 2)
        #expect(batch.searchLifecycle?.state == .inactive(lastEndedEpoch: 1))
        #expect(batch.presentation.searchUpdate == nil)
    }

    @Test("search lifecycle churn retains one fixed summary")
    func searchLifecycleChurnIsBounded() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        for index in 0..<100_000 {
            if index.isMultiple(of: 2) {
                accumulator.offer(.searchStarted(query: "query-\(index)"), for: surfaceID)
            } else {
                accumulator.offer(.searchEnded, for: surfaceID)
            }
        }

        #expect(accumulator.retainedEntryCount == 1)
        let batch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(batch.searchLifecycle?.transitionCount == 100_000)
        #expect(batch.searchLifecycle?.state == .inactive(lastEndedEpoch: 50_000))
    }

    @Test("search end after an earlier drain reports one barrier")
    func searchEndAcrossDrainsIsTruthful() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        accumulator.offer(.searchStarted(query: "needle"), for: surfaceID)
        let startedBatch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(startedBatch.searchLifecycle?.transitionCount == 1)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)

        #expect(accumulator.offer(.searchEnded, for: surfaceID) == .scheduled)
        let endedBatch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(endedBatch.searchLifecycle?.transitionCount == 1)
        #expect(endedBatch.searchLifecycle?.state == .inactive(lastEndedEpoch: 1))
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
        #expect(accumulator.retainedEntryCount == 0)
    }

    @Test("concurrent offers are linearized without retained debt")
    func concurrentOffersAreLinearized() async throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<20 {
                group.addTask {
                    for sample in 0..<5000 {
                        accumulator.offer(
                            .mouseShape(.other(rawValue: UInt32(worker * 5000 + sample))), for: surfaceID)
                    }
                }
            }
        }

        #expect(scheduler.scheduledSurfaceIDs == [surfaceID])
        let batch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(batch.metrics.offeredCount == 100_000)
        #expect(batch.metrics.replacedCount == 99_999)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
        #expect(accumulator.retainedEntryCount == 0)
    }

    @Test("cleanup removes only the matching surface lifetime")
    func cleanupIsLifetimeScoped() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let oldSurfaceID = UUIDv7.generate()
        let replacementSurfaceID = UUIDv7.generate()

        accumulator.offer(.mouseShape(.text), for: oldSurfaceID)
        accumulator.offer(.mouseShape(.pointer), for: replacementSurfaceID)
        accumulator.removeSurface(oldSurfaceID)
        #expect(accumulator.offer(.searchMatches(7), for: oldSurfaceID) == .rejectedInactiveSearch)

        #expect(accumulator.beginDrain(for: oldSurfaceID) == nil)
        #expect(accumulator.retainedEntryCount == 1)
        let replacement = try #require(accumulator.beginDrain(for: replacementSurfaceID))
        #expect(replacement.presentation.mouseShape == .pointer)
    }

    @Test("context transition detaches earlier evidence from later samples")
    func contextTransitionSeparatesActivityEpochs() throws {
        let accumulator = TerminalLocalActionAccumulator { _ in }
        let surfaceID = UUIDv7.generate()
        let before = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 30
        )
        let after = TerminalActivityProjectionContext(
            isAttended: true,
            isAgentClassified: true,
            outputBurstThreshold: 30
        )
        accumulator.offer(
            .scrollbar(ScrollbarState(top: 60, bottom: 100, total: 100), observedAtMilliseconds: 1000),
            for: surfaceID
        )

        let detached = try #require(
            accumulator.detachActivityBeforeControl(
                for: surfaceID,
                contextBeforeControl: before,
                contextAfterControl: after
            )
        )
        accumulator.offer(
            .scrollbar(ScrollbarState(top: 80, bottom: 120, total: 120), observedAtMilliseconds: 1100),
            for: surfaceID
        )
        let laterBatch = try #require(accumulator.beginDrain(for: surfaceID))

        #expect(detached.context == before)
        #expect(detached.latestState.total == 100)
        #expect(laterBatch.activityContext == after)
        #expect(laterBatch.activity?.latestTotalRows == 120)
    }
}

private final class DrainScheduleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID] = []

    var scheduledSurfaceIDs: [UUID] {
        lock.withLock { storage }
    }

    func record(_ surfaceID: UUID) {
        lock.withLock {
            storage.append(surfaceID)
        }
    }
}
