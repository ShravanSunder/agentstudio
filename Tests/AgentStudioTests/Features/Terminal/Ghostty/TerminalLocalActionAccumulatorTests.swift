import Foundation
import Testing

@testable import AgentStudio

@Suite("Terminal local action accumulator")
struct TerminalLocalActionAccumulatorTests {
    @Test("title drain admission reserves explicit slack before the publication maximum")
    func titleDrainAdmissionReservesPublicationSlack() {
        #expect(TerminalLocalActionDrainScheduler.titlePublicationMaximumMilliseconds == 250)
        #expect(TerminalLocalActionDrainScheduler.titleAdmissionSlackMilliseconds == 25)
        #expect(TerminalLocalActionDrainScheduler.titleDrainAdmissionDelayMilliseconds == 225)
    }

    @Test("title-only offers request one title-window drain")
    func titleOnlyOffersRequestOneTitleWindowDrain() {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        #expect(accumulator.offer(.titleChanged("first"), for: surfaceID) == .scheduled)
        #expect(accumulator.offer(.titleChanged("second"), for: surfaceID) == .coalesced)
        #expect(accumulator.offer(.tabTitleChanged("third"), for: surfaceID) == .coalesced)

        #expect(scheduler.recordedSchedules == [.init(surfaceID: surfaceID, schedule: .titleWindow)])
    }

    @Test("presentation activity and search offers request immediate drains")
    func nonTitleOffersRequestImmediateDrains() {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let presentationSurfaceID = UUIDv7.generate()
        let activitySurfaceID = UUIDv7.generate()
        let searchSurfaceID = UUIDv7.generate()

        #expect(accumulator.offer(.mouseShape(.text), for: presentationSurfaceID) == .scheduled)
        #expect(
            accumulator.offer(
                .scrollbar(
                    ScrollbarState(top: 80, bottom: 100, total: 100),
                    observedAtMilliseconds: 1
                ),
                for: activitySurfaceID
            ) == .scheduled
        )
        #expect(accumulator.offer(.searchStarted(query: "needle"), for: searchSurfaceID) == .scheduled)

        #expect(
            scheduler.recordedSchedules == [
                .init(surfaceID: presentationSurfaceID, schedule: .immediate),
                .init(surfaceID: activitySurfaceID, schedule: .immediate),
                .init(surfaceID: searchSurfaceID, schedule: .immediate),
            ]
        )
    }

    @Test("immediate work upgrades a scheduled title window exactly once")
    func immediateWorkUpgradesScheduledTitleWindowOnce() {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        #expect(accumulator.offer(.titleChanged("title"), for: surfaceID) == .scheduled)
        #expect(accumulator.offer(.mouseShape(.text), for: surfaceID) == .coalesced)
        #expect(accumulator.offer(.searchStarted(query: "needle"), for: surfaceID) == .coalesced)

        #expect(
            scheduler.recordedSchedules == [
                .init(surfaceID: surfaceID, schedule: .titleWindow),
                .init(surfaceID: surfaceID, schedule: .immediate),
            ]
        )
    }

    @Test("title deadline registration and immediate upgrade admit one drain without scheduler debt")
    func titleDeadlineAndImmediateUpgradeConvergeOnOneDrain() async throws {
        let surfaceID = UUIDv7.generate()
        let controlledExecutor = ControlledDrainSchedulerExecutor()
        let drainOwner = TerminalSchedulerTestDrainOwner()
        let scheduler = TerminalLocalActionDrainScheduler(
            drain: drainOwner.drain,
            scheduleTitleDeadline: controlledExecutor.recordTitleDeadline,
            enqueueMainActorDrain: controlledExecutor.recordMainActorAdmission
        )
        let accumulator = TerminalLocalActionAccumulator(
            scheduleDrain: scheduler.schedule,
            scheduleFollowUpDrain: scheduler.scheduleFollowUp,
            cancelScheduledTitleDrain: scheduler.cancel
        )
        drainOwner.install(accumulator)

        accumulator.offer(.titleChanged("title"), for: surfaceID)
        #expect(controlledExecutor.pendingTitleDeadlineCount == 1)
        try controlledExecutor.claimNextTitleDeadline()
        #expect(controlledExecutor.pendingMainActorAdmissionCount == 1)

        // Immediate work lands after the deadline claim but before its queued
        // MainActor operation begins. It must reuse the live claim.
        accumulator.offer(.mouseShape(.text), for: surfaceID)
        #expect(controlledExecutor.pendingMainActorAdmissionCount == 1)

        try await controlledExecutor.runNextMainActorAdmission()
        #expect(drainOwner.recordedSurfaceIDs == [surfaceID])
        #expect(scheduler.pendingDrainClaimCount == 0)
        #expect(accumulator.pendingSurfaceCount == 0)
        #expect(accumulator.retainedEntryCount == 0)
    }

    @Test("title work does not reschedule an immediate drain")
    func titleWorkDoesNotRescheduleImmediateDrain() {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        #expect(accumulator.offer(.mouseVisibility(false), for: surfaceID) == .scheduled)
        #expect(accumulator.offer(.titleChanged("title"), for: surfaceID) == .coalesced)
        #expect(accumulator.offer(.tabTitleChanged("tab"), for: surfaceID) == .coalesced)

        #expect(scheduler.recordedSchedules == [.init(surfaceID: surfaceID, schedule: .immediate)])
    }

    @Test("follow-up drain schedule reflects the pending action class")
    func followUpDrainScheduleReflectsPendingActionClass() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let titleOnlySurfaceID = UUIDv7.generate()
        let mixedSurfaceID = UUIDv7.generate()
        let nonTitleSurfaceID = UUIDv7.generate()

        accumulator.offer(.titleChanged("initial"), for: titleOnlySurfaceID)
        _ = try #require(accumulator.beginDrain(for: titleOnlySurfaceID))
        accumulator.offer(.tabTitleChanged("follow-up"), for: titleOnlySurfaceID)
        #expect(accumulator.finishDrain(for: titleOnlySurfaceID) == .followUpScheduled)

        accumulator.offer(.titleChanged("initial"), for: mixedSurfaceID)
        _ = try #require(accumulator.beginDrain(for: mixedSurfaceID))
        accumulator.offer(.titleChanged("follow-up"), for: mixedSurfaceID)
        accumulator.offer(.mouseShape(.pointer), for: mixedSurfaceID)
        #expect(accumulator.finishDrain(for: mixedSurfaceID) == .followUpScheduled)

        accumulator.offer(.mouseShape(.text), for: nonTitleSurfaceID)
        _ = try #require(accumulator.beginDrain(for: nonTitleSurfaceID))
        accumulator.offer(.mouseVisibility(false), for: nonTitleSurfaceID)
        #expect(accumulator.finishDrain(for: nonTitleSurfaceID) == .followUpScheduled)

        #expect(
            scheduler.recordedSchedules == [
                .init(surfaceID: titleOnlySurfaceID, schedule: .titleWindow),
                .init(surfaceID: titleOnlySurfaceID, schedule: .titleWindow),
                .init(surfaceID: mixedSurfaceID, schedule: .titleWindow),
                .init(surfaceID: mixedSurfaceID, schedule: .immediate),
                .init(surfaceID: nonTitleSurfaceID, schedule: .immediate),
                .init(surfaceID: nonTitleSurfaceID, schedule: .immediate),
            ]
        )
    }

    @Test("title callbacks retain independent latest runtime and surface values")
    func titleCallbacksRetainIndependentLatestValues() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        #expect(accumulator.offer(.titleChanged("window"), for: surfaceID) == .scheduled)
        #expect(accumulator.offer(.tabTitleChanged("tab"), for: surfaceID) == .coalesced)

        #expect(scheduler.scheduledSurfaceIDs == [surfaceID])
        #expect(accumulator.hasPendingActions(for: surfaceID))
        let batch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(batch.titleMetadata?.runtimeTitle == .tabTitleChanged("tab"))
        #expect(batch.titleMetadata?.surfaceTitle == "window")
        #expect(batch.metrics.offeredCount == 2)
        #expect(batch.metrics.replacedCount == 1)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
        #expect(!accumulator.hasPendingActions(for: surfaceID))
        #expect(accumulator.retainedEntryCount == 0)

        let tabOnlySurfaceID = UUIDv7.generate()
        accumulator.offer(.tabTitleChanged("tab-only"), for: tabOnlySurfaceID)
        let tabOnlyBatch = try #require(accumulator.beginDrain(for: tabOnlySurfaceID))
        #expect(tabOnlyBatch.titleMetadata?.runtimeTitle == .tabTitleChanged("tab-only"))
        #expect(tabOnlyBatch.titleMetadata?.surfaceTitle == nil)
    }

    @Test("exact title barriers report only exact title accounting and no extra MainActor task")
    func exactTitleBarrierAccountingIsHonest() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        accumulator.offer(.mouseShape(.text), for: surfaceID)
        accumulator.offer(.titleChanged("A"), for: surfaceID)
        accumulator.offer(.titleChanged("A"), for: surfaceID)
        accumulator.offer(.tabTitleChanged("C"), for: surfaceID)

        let barrier = try #require(accumulator.detachTitleBeforeExactBarrier(for: surfaceID))
        #expect(barrier.metadata.runtimeTitle == .tabTitleChanged("C"))
        #expect(barrier.metadata.surfaceTitle == "A")
        #expect(barrier.metrics.offeredCount == 3)
        #expect(barrier.metrics.replacedCount == 1)
        #expect(barrier.metrics.equalSuppressedCount == 1)
        #expect(barrier.metrics.scheduledDrainCount == 0)
        #expect(barrier.metrics.followUpDrainCount == 0)
        let performanceSnapshot = Ghostty.ActionRouter.terminalAccumulatorDrainPerformanceSnapshot(for: barrier)
        #expect(performanceSnapshot.drainClass == .exactBarrier)
        #expect(performanceSnapshot.mainActorTaskCount == 0)
        #expect(performanceSnapshot.activityAggregateCount == 0)
        #expect(performanceSnapshot.retainedEntryCount == 2)
        #expect(
            Ghostty.ActionRouter.terminalAccumulatorQueueAge(
                firstOfferedAtNanoseconds: barrier.firstOfferedAtNanoseconds,
                currentUptimeNanoseconds: barrier.firstOfferedAtNanoseconds + 50
            ) == .nanoseconds(50)
        )

        let remainingBatch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(remainingBatch.presentation.mouseShape == .text)
        #expect(remainingBatch.titleMetadata == nil)
        #expect(remainingBatch.metrics.offeredCount == 1)
        #expect(remainingBatch.metrics.replacedCount == 0)
        #expect(remainingBatch.metrics.equalSuppressedCount == 0)
        #expect(remainingBatch.metrics.scheduledDrainCount == 1)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
    }

    @Test("metric subtraction rejects values outside the pending batch")
    func metricSubtractionRequiresSubset() {
        let pendingMetrics = TerminalLocalAccumulatorMetrics(
            offeredCount: 2,
            replacedCount: 1,
            equalSuppressedCount: 0,
            scheduledDrainCount: 1,
            followUpDrainCount: 0
        )
        let invalidTitleMetrics = TerminalLocalAccumulatorMetrics(
            offeredCount: 3,
            replacedCount: 1,
            equalSuppressedCount: 0,
            scheduledDrainCount: 1,
            followUpDrainCount: 0
        )

        #expect(pendingMetrics.subtracting(invalidTitleMetrics) == nil)
    }

    @Test("exact title barriers leave mixed follow-up scheduling metrics with the remaining batch")
    func exactTitleBarrierPreservesMixedFollowUpMetrics() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        accumulator.offer(.mouseShape(.text), for: surfaceID)
        _ = try #require(accumulator.beginDrain(for: surfaceID))
        accumulator.offer(.titleChanged("A"), for: surfaceID)
        accumulator.offer(.mouseVisibility(true), for: surfaceID)
        #expect(accumulator.finishDrain(for: surfaceID) == .followUpScheduled)

        let barrier = try #require(accumulator.detachTitleBeforeExactBarrier(for: surfaceID))
        #expect(barrier.metrics.followUpDrainCount == 0)

        let remainingBatch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(remainingBatch.presentation.mouseVisibility == true)
        #expect(remainingBatch.titleMetadata == nil)
        #expect(remainingBatch.metrics.followUpDrainCount == 1)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
    }

    @Test("large title burst schedules one bounded drain and retains the latest kind")
    func largeTitleBurstIsBounded() throws {
        let scheduler = DrainScheduleRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: scheduler.record)
        let surfaceID = UUIDv7.generate()

        for index in 0..<100_000 {
            if index.isMultiple(of: 2) {
                accumulator.offer(.titleChanged("window-\(index)"), for: surfaceID)
            } else {
                accumulator.offer(.tabTitleChanged("tab-\(index)"), for: surfaceID)
            }
        }

        #expect(scheduler.scheduledSurfaceIDs == [surfaceID])
        #expect(accumulator.retainedEntryCount <= TerminalLocalActionAccumulator.maximumRetainedEntriesPerSurface)
        let batch = try #require(accumulator.beginDrain(for: surfaceID))
        #expect(Ghostty.ActionRouter.terminalAccumulatorDrainClass(for: batch) == .titleWindow)
        #expect(batch.titleMetadata?.runtimeTitle == .tabTitleChanged("tab-99999"))
        #expect(batch.titleMetadata?.surfaceTitle == "window-99998")
        #expect(batch.metrics.offeredCount == 100_000)
        #expect(batch.metrics.replacedCount == 99_999)
        #expect(accumulator.finishDrain(for: surfaceID) == .idle)
    }

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
        #expect(Ghostty.ActionRouter.terminalAccumulatorDrainClass(for: batch) == .immediate)
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

        accumulator.offer(.titleChanged("stale"), for: oldSurfaceID)
        accumulator.removeSurface(oldSurfaceID)
        #expect(accumulator.beginDrain(for: oldSurfaceID) == nil)
    }

    @Test("context transition detaches earlier evidence from later samples")
    func contextTransitionSeparatesActivityEpochs() throws {
        let accumulator = TerminalLocalActionAccumulator { _, _ in }
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
    private var storage: [RecordedDrainSchedule] = []

    var recordedSchedules: [RecordedDrainSchedule] {
        lock.withLock { storage }
    }

    var scheduledSurfaceIDs: [UUID] {
        lock.withLock { storage.map(\.surfaceID) }
    }

    func record(_ surfaceID: UUID, _ schedule: TerminalLocalDrainSchedule) {
        lock.withLock {
            storage.append(.init(surfaceID: surfaceID, schedule: schedule))
        }
    }
}

private final class ControlledDrainSchedulerExecutor: @unchecked Sendable {
    private let lock = NSLock()
    private var titleDeadlines: [DispatchWorkItem] = []
    private var mainActorAdmissions: [TerminalMainActorDrainOperation] = []

    var pendingTitleDeadlineCount: Int {
        lock.withLock { titleDeadlines.count }
    }

    var pendingMainActorAdmissionCount: Int {
        lock.withLock { mainActorAdmissions.count }
    }

    func recordTitleDeadline(_ workItem: DispatchWorkItem) {
        lock.withLock {
            titleDeadlines.append(workItem)
        }
    }

    func recordMainActorAdmission(_ operation: @escaping TerminalMainActorDrainOperation) {
        lock.withLock {
            mainActorAdmissions.append(operation)
        }
    }

    func claimNextTitleDeadline() throws {
        let workItem = try #require(lock.withLock { titleDeadlines.isEmpty ? nil : titleDeadlines.removeFirst() })
        workItem.perform()
    }

    func runNextMainActorAdmission() async throws {
        let operation = try #require(
            lock.withLock { mainActorAdmissions.isEmpty ? nil : mainActorAdmissions.removeFirst() }
        )
        await operation()
    }
}

private final class TerminalSchedulerTestDrainOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator: TerminalLocalActionAccumulator?
    private var drainedSurfaceIDs: [UUID] = []

    var recordedSurfaceIDs: [UUID] {
        lock.withLock { drainedSurfaceIDs }
    }

    func install(_ accumulator: TerminalLocalActionAccumulator) {
        lock.withLock {
            self.accumulator = accumulator
        }
    }

    @MainActor
    func drain(_ surfaceID: UUID) async {
        guard let accumulator = lock.withLock({ accumulator }) else { return }
        guard accumulator.beginDrain(for: surfaceID) != nil else { return }
        lock.withLock {
            drainedSurfaceIDs.append(surfaceID)
        }
        _ = accumulator.finishDrain(for: surfaceID)
    }
}

private struct RecordedDrainSchedule: Equatable {
    let surfaceID: UUID
    let schedule: TerminalLocalDrainSchedule
}
