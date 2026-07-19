import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Terminal activity projector", .serialized)
struct TerminalActivityProjectorTests {
    private final class OutcomeRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedOutcomes: [TerminalActivityProjectionOutcome] = []
        private var recordedBatches: [[TerminalActivityProjectionOutcome]] = []

        var outcomes: [TerminalActivityProjectionOutcome] {
            lock.withLock { recordedOutcomes }
        }

        var batches: [[TerminalActivityProjectionOutcome]] {
            lock.withLock { recordedBatches }
        }

        func record(_ batch: [TerminalActivityProjectionOutcome]) {
            lock.withLock {
                recordedBatches.append(batch)
                recordedOutcomes.append(contentsOf: batch)
            }
        }
    }

    @Test("aggregate admission retains fixed state per pane")
    func aggregateAdmissionIsBoundedPerPane() async {
        let clock = TestPushClock()
        let projector = TerminalActivityProjector(clock: clock)
        let recorder = OutcomeRecorder()
        await projector.configure { outcomes in recorder.record(outcomes) }
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 30
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        for index in 0..<1000 {
            let aggregate = makeAggregate(firstTotal: index, latestTotal: index + 1)
            await projector.ingest(
                surfaceID: surfaceID,
                paneID: paneID,
                aggregate: aggregate,
                latestState: ScrollbarState(top: index, bottom: index + 1, total: index + 1),
                context: context
            )
        }

        #expect(await projector.retainedPaneCount == 1)
        #expect(await projector.scheduledTimerCount == 2)
        await projector.reset()
    }

    @Test("closing an old surface cannot retire its pane replacement")
    func oldSurfaceCloseDoesNotRetireReplacement() async {
        let projector = TerminalActivityProjector(clock: TestPushClock())
        let recorder = OutcomeRecorder()
        await projector.configure { outcomes in recorder.record(outcomes) }
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: false,
            outputBurstThreshold: 30
        )
        let paneID = UUIDv7.generate()
        let oldSurfaceID = UUIDv7.generate()
        let replacementSurfaceID = UUIDv7.generate()
        let aggregate = makeAggregate(firstTotal: 100, latestTotal: 120)

        await projector.ingest(
            surfaceID: oldSurfaceID,
            paneID: paneID,
            aggregate: aggregate,
            latestState: ScrollbarState(top: 80, bottom: 120, total: 120),
            context: context
        )
        await projector.ingest(
            surfaceID: replacementSurfaceID,
            paneID: paneID,
            aggregate: aggregate,
            latestState: ScrollbarState(top: 80, bottom: 120, total: 120),
            context: context
        )
        await projector.closeSurface(surfaceID: oldSurfaceID, paneID: paneID)
        await projector.markObserved(surfaceID: oldSurfaceID, paneID: paneID)

        #expect(await projector.retainedPaneCount == 1)
        #expect(await projector.scheduledTimerCount == 1)

        await projector.closeSurface(surfaceID: replacementSurfaceID, paneID: paneID)
        #expect(await projector.retainedPaneCount == 0)
    }

    @Test("equal compact state and first output are emitted once")
    func equalOutcomesAreSuppressed() async {
        let projector = TerminalActivityProjector(clock: TestPushClock())
        let recorder = OutcomeRecorder()
        await projector.configure { outcomes in recorder.record(outcomes) }
        let context = TerminalActivityProjectionContext(
            isAttended: true,
            isAgentClassified: false,
            outputBurstThreshold: 30
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()
        let aggregate = makeAggregate(firstTotal: 100, latestTotal: 100)
        let state = ScrollbarState(top: 60, bottom: 100, total: 100)

        await projector.ingest(
            surfaceID: surfaceID,
            paneID: paneID,
            aggregate: aggregate,
            latestState: state,
            context: context
        )
        await projector.ingest(
            surfaceID: surfaceID,
            paneID: paneID,
            aggregate: aggregate,
            latestState: state,
            context: context
        )

        let compactCount = recorder.outcomes.count { outcome in
            if case .compactStateChanged = outcome { return true }
            return false
        }
        let firstOutputCount = recorder.outcomes.count { outcome in
            if case .firstOutput = outcome { return true }
            return false
        }
        #expect(compactCount == 1)
        #expect(firstOutputCount == 1)
    }

    @Test("quiet settlement is derived by the projector actor")
    func quietSettlementIsProjectorOwned() async {
        let clock = TestPushClock()
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .milliseconds(750),
            clock: clock
        )
        let recorder = OutcomeRecorder()
        await projector.configure { outcomes in recorder.record(outcomes) }
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: false,
            outputBurstThreshold: 30
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.ingest(
            surfaceID: surfaceID,
            paneID: paneID,
            aggregate: makeAggregate(firstTotal: 100, latestTotal: 140),
            latestState: ScrollbarState(top: 100, bottom: 140, total: 140),
            context: context
        )
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(750))
        await assertEventuallyAsync("projector should emit one settled activity") {
            recorder.outcomes.contains { outcome in
                guard case .unseenActivitySettled(_, let outcomePaneID, let activity) = outcome else { return false }
                return activity.rowsAdded == 40 && outcomePaneID == paneID
            }
        }
    }

    @Test("ordered observation applies earlier evidence before clearing activity windows")
    func orderedObservationClearsEarlierEvidence() async {
        let projector = TerminalActivityProjector(clock: TestPushClock())
        let recorder = OutcomeRecorder()
        await projector.configure { outcomes in recorder.record(outcomes) }
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 30
        )

        await projector.applyOrderedControl(
            surfaceID: surfaceID,
            paneID: paneID,
            precedingAggregate: TerminalActivityAggregateInput(
                aggregate: makeAggregate(firstTotal: 100, latestTotal: 140),
                latestState: ScrollbarState(top: 100, bottom: 140, total: 140),
                context: context
            ),
            control: .observed
        )

        #expect(await projector.retainedPaneCount == 1)
        #expect(await projector.scheduledTimerCount == 0)
        #expect(
            recorder.outcomes.contains { outcome in
                if case .compactStateChanged = outcome { return true }
                return false
            }
        )
    }

    @Test("ordered close retires earlier evidence without post-close debt")
    func orderedCloseRetiresEarlierEvidence() async {
        let projector = TerminalActivityProjector(clock: TestPushClock())
        let recorder = OutcomeRecorder()
        await projector.configure { outcomes in recorder.record(outcomes) }
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.applyOrderedControl(
            surfaceID: surfaceID,
            paneID: paneID,
            precedingAggregate: TerminalActivityAggregateInput(
                aggregate: makeAggregate(firstTotal: 100, latestTotal: 140),
                latestState: ScrollbarState(top: 100, bottom: 140, total: 140),
                context: TerminalActivityProjectionContext(
                    isAttended: false,
                    isAgentClassified: true,
                    outputBurstThreshold: 30
                )
            ),
            control: .surfaceClosed
        )

        #expect(await projector.retainedPaneCount == 0)
        #expect(await projector.scheduledTimerCount == 0)
        #expect(
            recorder.outcomes.last == .surfaceClosed(surfaceID: surfaceID, paneID: paneID)
        )
    }

    @Test("sink-triggered later evidence cannot split the ordered outcome batch")
    func orderedControlDeliversOneNoninterleavedOutcomeBatch() async {
        let projector = TerminalActivityProjector(clock: TestPushClock())
        let recorder = OutcomeRecorder()
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: false,
            outputBurstThreshold: 30
        )
        var laterAggregateTask: Task<Void, Never>?
        await projector.configure { outcomes in
            recorder.record(outcomes)
            guard recorder.batches.count == 1 else { return }
            laterAggregateTask = Task {
                await projector.ingest(
                    surfaceID: surfaceID,
                    paneID: paneID,
                    aggregate: makeAggregate(firstTotal: 140, latestTotal: 180),
                    latestState: ScrollbarState(top: 140, bottom: 180, total: 180),
                    context: context
                )
            }
        }

        await projector.applyOrderedControl(
            surfaceID: surfaceID,
            paneID: paneID,
            precedingAggregate: TerminalActivityAggregateInput(
                aggregate: makeAggregate(firstTotal: 100, latestTotal: 140),
                latestState: ScrollbarState(top: 100, bottom: 140, total: 140),
                context: context
            ),
            control: .observed
        )
        await laterAggregateTask?.value

        #expect(await projector.scheduledTimerCount == 1)
        #expect(recorder.batches.count == 2)
        #expect(recorder.batches[0].count == 3)
        #expect(
            recorder.batches[0].map { outcome in
                switch outcome {
                case .compactStateChanged: return "compact"
                case .firstOutput: return "firstOutput"
                case .paneObservationChanged: return "observation"
                default: return "unexpected"
                }
            } == ["compact", "firstOutput", "observation"]
        )
        #expect(recorder.batches[1].count == 1)
        #expect(
            recorder.batches[1].allSatisfy { outcome in
                if case .compactStateChanged = outcome { return true }
                return false
            }
        )
        await projector.reset()
    }

    private func makeAggregate(firstTotal: Int, latestTotal: Int) -> TerminalScrollbarActivityAggregate {
        var aggregate = TerminalScrollbarActivityAggregate(
            state: ScrollbarState(top: max(0, firstTotal - 10), bottom: firstTotal, total: firstTotal),
            observedAtMilliseconds: 1000
        )
        aggregate.merge(
            state: ScrollbarState(top: max(0, latestTotal - 10), bottom: latestTotal, total: latestTotal),
            observedAtMilliseconds: 1100
        )
        return aggregate
    }
}
