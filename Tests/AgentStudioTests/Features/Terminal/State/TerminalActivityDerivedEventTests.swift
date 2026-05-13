import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalActivityRouter derived activity events", .serialized)
struct TerminalActivityDerivedEventTests {
    private final class MillisecondBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64

        init(_ value: Int64) {
            self.value = value
        }

        func set(_ value: Int64) {
            lock.withLock {
                self.value = value
            }
        }

        func get() -> Int64 {
            lock.withLock {
                value
            }
        }
    }

    private final class PaneSetBox: @unchecked Sendable {
        private let lock = NSLock()
        private var paneIds = Set<UUID>()

        func insert(_ paneId: UUID) {
            _ = lock.withLock {
                paneIds.insert(paneId)
            }
        }

        func contains(_ paneId: UUID) -> Bool {
            lock.withLock {
                paneIds.contains(paneId)
            }
        }
    }

    @Test("scrollback growth does not emit unseen activity before quiet")
    func scrollbackGrowthDoesNotEmitUnseenActivityBeforeQuiet() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(stream: await bus.subscribe())
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock
        )
        let paneId = PaneId()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        let initialSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbackBurst(paneId: paneId, totals: [100, 120, 140], to: bus)
        await waitForLatestRows(140, paneId: paneId, atom: atom)
        await waitForLatestPendingDebounce(
            clock: clock,
            initialGeneration: initialSleepGeneration,
            eventCount: 3
        )

        #expect(await derivedActivities(from: subscriber).isEmpty)

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("scrollback growth emits one settled activity after quiet")
    func scrollbackGrowthEmitsOneSettledActivityAfterQuiet() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(stream: await bus.subscribe())
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(2000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        let initialSleepGeneration = clock.scheduledSleepGeneration
        for (index, totalRows) in [100, 120, 140].enumerated() {
            nowMilliseconds.set(2000 + Int64(index * 100))
            _ = await bus.post(
                .pane(
                    .test(
                        event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: totalRows))),
                        paneId: paneId,
                        paneKind: .terminal,
                        seq: UInt64(index + 1)
                    )
                )
            )
            await waitForLatestRows(totalRows, paneId: paneId, atom: atom)
        }
        await waitForLatestPendingDebounce(
            clock: clock,
            initialGeneration: initialSleepGeneration,
            eventCount: 3
        )
        clock.advance(by: .milliseconds(749))
        #expect(await derivedActivities(from: subscriber).isEmpty)

        clock.advance(by: .milliseconds(1))
        await assertEventuallyAsync("quiet settle should emit one derived activity") {
            await derivedActivities(from: subscriber).count == 1
        }
        let activity = try #require(await derivedActivities(from: subscriber).first)
        #expect(activity.rowsAdded == 40)
        #expect(activity.thresholdRows == 30)
        #expect(activity.eventCount == 3)
        #expect(activity.latestRows == 140)
        #expect(activity.baselineRows == 100)
        #expect(activity.startedAtMilliseconds == 2000)
        #expect(activity.settledAtMilliseconds == 2000 + 200 + 750)

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("observing pane before quiet cancels settled activity")
    func observingPaneBeforeQuietCancelsSettledActivity() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(stream: await bus.subscribe())
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let paneId = PaneId()
        let attendedPaneIds = PaneSetBox()
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            isPaneCurrentlyAttended: { attendedPaneIds.contains($0) },
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock
        )

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        let initialSleepGeneration = clock.scheduledSleepGeneration
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100))),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 1
                )
            )
        )
        await waitForLatestPendingDebounce(
            clock: clock,
            initialGeneration: initialSleepGeneration,
            eventCount: 1
        )

        attendedPaneIds.insert(paneId.uuid)
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 140))),
                    paneId: paneId,
                    paneKind: .terminal,
                    seq: 2
                )
            )
        )
        await clock.waitForPendingSleepCount(exactly: 0)

        clock.advance(by: .milliseconds(750))

        #expect(await derivedActivities(from: subscriber).isEmpty)

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("settled activity events use independent monotonic source sequence")
    func settledActivityEventsUseIndependentMonotonicSourceSequence() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(stream: await bus.subscribe())
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock
        )
        let paneId = PaneId()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        let firstInitialSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbackBurst(paneId: paneId, totals: [100, 120, 140], to: bus)
        await waitForLatestRows(140, paneId: paneId, atom: atom)
        await waitForLatestPendingDebounce(
            clock: clock,
            initialGeneration: firstInitialSleepGeneration,
            eventCount: 3
        )
        clock.advance(by: .milliseconds(750))
        await assertEventuallyAsync("first window should settle") {
            await derivedPaneEvents(from: subscriber).count == 1
        }

        router.markUnseenActivityObserved(paneId: paneId.uuid)
        let secondInitialSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbackBurst(paneId: paneId, totals: [200, 220, 240], to: bus, startingSeq: 10)
        await waitForLatestRows(240, paneId: paneId, atom: atom)
        await waitForLatestPendingDebounce(
            clock: clock,
            initialGeneration: secondInitialSleepGeneration,
            eventCount: 3
        )
        clock.advance(by: .milliseconds(750))

        await assertEventuallyAsync("second window should settle") {
            await derivedPaneEvents(from: subscriber).count == 2
        }
        let events = await derivedPaneEvents(from: subscriber)
        #expect(
            events.map(\.source) == [
                .system(.builtin(.terminalActivityRouter)),
                .system(.builtin(.terminalActivityRouter)),
            ])
        #expect(events.map(\.seq) == [1, 2])

        await router.stop()
        await subscriber.shutdown()
    }

    private func derivedActivities(
        from subscriber: RecordingSubscriber<RuntimeEnvelope>
    ) async -> [TerminalSettledActivity] {
        await derivedPaneEvents(from: subscriber).map(\.activity)
    }

    private func derivedPaneEvents(
        from subscriber: RecordingSubscriber<RuntimeEnvelope>
    ) async -> [(source: EventSource, seq: UInt64, activity: TerminalSettledActivity)] {
        RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot()).compactMap { record in
            guard case .terminalActivity(.unseenActivitySettled(let activity)) = record.event else {
                return nil
            }
            return (source: record.source, seq: record.seq, activity: activity)
        }
    }

    private func postScrollbackBurst(
        paneId: PaneId,
        totals: [Int],
        to bus: EventBus<RuntimeEnvelope>,
        startingSeq: UInt64 = 1
    ) async {
        for (index, totalRows) in totals.enumerated() {
            _ = await bus.post(
                .pane(
                    .test(
                        event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: totalRows))),
                        paneId: paneId,
                        paneKind: .terminal,
                        seq: startingSeq + UInt64(index)
                    )
                )
            )
        }
    }

    private func waitForLatestRows(
        _ latestRows: Int,
        paneId: PaneId,
        atom: TerminalActivityAtom
    ) async {
        await assertEventuallyMain("terminal activity atom should observe latest rows") {
            atom.snapshot(for: paneId.uuid)?.scrollbarState?.total == latestRows
        }
    }

    private func waitForLatestPendingDebounce(
        clock: TestPushClock,
        initialGeneration: Int,
        eventCount: Int
    ) async {
        let latestPendingGeneration = initialGeneration + eventCount - 1
        await clock.waitForPendingSleepGeneration(latestPendingGeneration)
    }
}
