import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalActivityRouter agent settled heuristic", .serialized)
struct TerminalActivityAgentSettledHeuristicTests {
    private final class MillisecondBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64

        init(_ value: Int64) {
            self.value = value
        }

        func set(_ value: Int64) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> Int64 {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    @Test("non-agent qualifying output emits blue activity instead of yellow")
    func nonAgentQualifyingOutputEmitsBlueActivityInsteadOfYellow() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(
            subscription: await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function))
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            agentSettledQuietDuration: .seconds(180),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        let initialSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 100, seq: 1, paneKind: .terminal, paneId: paneId, to: bus)
        nowMilliseconds.set(1100)
        await postScrollbar(total: 700, seq: 2, paneKind: .terminal, paneId: paneId, to: bus)
        await waitForLatestPendingDebounce(
            clock: clock,
            initialGeneration: initialSleepGeneration,
            eventCount: 2
        )
        clock.advance(by: .milliseconds(750))

        await assertEventuallyAsync("non-agent output should emit blue settled activity") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .unseenActivitySettled = $0 { return true }
                return false
            }
        }
        #expect(
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            } == false)

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("agent qualifying output promotes yellow after quiet and revokes on later output")
    func agentQualifyingOutputPromotesYellowAfterQuietAndRevokesOnLaterOutput() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(
            subscription: await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function))
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            agentSettledQuietDuration: .seconds(180),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        await postScrollbar(total: 100, seq: 1, paneKind: .agent, paneId: paneId, to: bus)
        await clock.waitForPendingSleepCount(atLeast: 2)
        nowMilliseconds.set(62_000)
        let secondEventSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 700, seq: 2, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: secondEventSleepGeneration)
        clock.advance(by: .milliseconds(750))
        #expect(
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            } == false)

        clock.advance(by: .seconds(180))
        await assertEventuallyAsync("agent output should promote yellow after long quiet") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            }
        }

        nowMilliseconds.set(182_000)
        await postScrollbar(total: 720, seq: 3, paneKind: .agent, paneId: paneId, to: bus)
        await assertEventuallyAsync("later agent output should revoke yellow") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityRevoked = $0 { return true }
                return false
            }
        }

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("layout terminal signals do not revoke visible yellow settled attention")
    func layoutTerminalSignalsDoNotRevokeVisibleYellowSettledAttention() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(
            subscription: await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function))
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            agentSettledQuietDuration: .seconds(180),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        await postScrollbar(total: 100, seq: 1, paneKind: .agent, paneId: paneId, to: bus)
        await clock.waitForPendingSleepCount(atLeast: 2)
        nowMilliseconds.set(62_000)
        let secondEventSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 700, seq: 2, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: secondEventSleepGeneration)
        clock.advance(by: .milliseconds(750))
        #expect(
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            } == false)

        clock.advance(by: .seconds(180))
        await assertEventuallyAsync("agent output should promote yellow after long quiet") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            }
        }

        await postTerminal(
            .sizeLimitChanged(
                TerminalSizeConstraints(
                    minWidth: 640,
                    minHeight: 480,
                    maxWidth: 1440,
                    maxHeight: 900
                )
            ),
            seq: 3,
            paneKind: .agent,
            paneId: paneId,
            to: bus
        )

        #expect(
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityRevoked = $0 { return true }
                return false
            } == false)

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("later scrollbar observation revokes visible yellow settled attention even without row growth")
    func laterScrollbarObservationRevokesVisibleYellowSettledAttentionEvenWithoutRowGrowth() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(
            subscription: await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function))
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            agentSettledQuietDuration: .seconds(180),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        await postScrollbar(total: 100, seq: 1, paneKind: .agent, paneId: paneId, to: bus)
        await clock.waitForPendingSleepCount(atLeast: 2)
        nowMilliseconds.set(62_000)
        let secondEventSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 700, seq: 2, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: secondEventSleepGeneration)
        clock.advance(by: .milliseconds(750))
        #expect(
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            } == false)

        clock.advance(by: .seconds(180))
        await assertEventuallyAsync("agent output should promote yellow after long quiet") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            }
        }

        nowMilliseconds.set(242_000)
        await postScrollbar(total: 700, seq: 3, paneKind: .agent, paneId: paneId, to: bus)
        await assertEventuallyAsync("later output proxy should revoke yellow") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityRevoked = $0 { return true }
                return false
            }
        }

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("revoked yellow settled attention does not re-promote until pane is observed")
    func revokedYellowSettledAttentionDoesNotRepromoteUntilPaneIsObserved() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(
            subscription: await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function))
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            agentSettledQuietDuration: .seconds(180),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        await postScrollbar(total: 100, seq: 1, paneKind: .agent, paneId: paneId, to: bus)
        await clock.waitForPendingSleepCount(atLeast: 2)
        nowMilliseconds.set(62_000)
        let secondEventSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 700, seq: 2, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: secondEventSleepGeneration)
        clock.advance(by: .milliseconds(750))
        clock.advance(by: .seconds(180))
        await assertEventuallyAsync("agent output should promote yellow after long quiet") {
            await Self.agentSettledPromotionCount(from: subscriber) == 1
        }

        nowMilliseconds.set(242_000)
        await postScrollbar(total: 700, seq: 3, paneKind: .agent, paneId: paneId, to: bus)
        await assertEventuallyAsync("later output proxy should revoke yellow") {
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityRevoked = $0 { return true }
                return false
            }
        }

        nowMilliseconds.set(304_000)
        await postScrollbar(total: 1300, seq: 4, paneKind: .agent, paneId: paneId, to: bus)
        clock.advance(by: .seconds(180))
        #expect(await Self.agentSettledPromotionCount(from: subscriber) == 1)

        router.markUnseenActivityObserved(paneId: paneId.uuid)
        nowMilliseconds.set(366_000)
        let observedCycleStartGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 1300, seq: 5, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: observedCycleStartGeneration)
        nowMilliseconds.set(428_000)
        let observedCycleSecondEventGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 1900, seq: 6, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: observedCycleSecondEventGeneration)
        clock.advance(by: .seconds(180))
        await assertEventuallyAsync("observed pane should allow future yellow settled attention") {
            await Self.agentSettledPromotionCount(from: subscriber) == 2
        }

        await router.stop()
        await subscriber.shutdown()
    }

    @Test("observing pane before yellow quiet cancels stale agent-settled promotion")
    func observingPaneBeforeYellowQuietCancelsStaleAgentSettledPromotion() async {
        let bus = EventBus<RuntimeEnvelope>()
        let subscriber = RecordingSubscriber(
            subscription: await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function))
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let nowMilliseconds = MillisecondBox(1000)
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            unseenActivityDebounceDuration: .milliseconds(750),
            agentSettledQuietDuration: .seconds(180),
            unseenActivityClock: clock,
            nowMilliseconds: { nowMilliseconds.get() }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await waitForBusSubscriberCount(bus, atLeast: 2)
        await postScrollbar(total: 100, seq: 1, paneKind: .agent, paneId: paneId, to: bus)
        await clock.waitForPendingSleepCount(atLeast: 2)
        nowMilliseconds.set(62_000)
        let secondEventSleepGeneration = clock.scheduledSleepGeneration
        await postScrollbar(total: 700, seq: 2, paneKind: .agent, paneId: paneId, to: bus)
        await waitForReplacementSleepPair(clock: clock, scheduledAfter: secondEventSleepGeneration)

        router.markUnseenActivityObserved(paneId: paneId.uuid)
        await clock.waitForPendingSleepCount(exactly: 0)

        clock.advance(by: .seconds(180))

        #expect(
            await Self.terminalActivityEvents(from: subscriber).contains {
                if case .agentSettledActivityPromoted = $0 { return true }
                return false
            } == false)

        await router.stop()
        await subscriber.shutdown()
    }

    private func postScrollbar(
        total: Int,
        seq: UInt64,
        paneKind: PaneContentType,
        paneId: PaneId,
        to bus: EventBus<RuntimeEnvelope>
    ) async {
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: total))),
                    paneId: paneId,
                    paneKind: paneKind,
                    seq: seq
                )
            )
        )
    }

    private func postTerminal(
        _ event: GhosttyEvent,
        seq: UInt64,
        paneKind: PaneContentType,
        paneId: PaneId,
        to bus: EventBus<RuntimeEnvelope>
    ) async {
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(event),
                    paneId: paneId,
                    paneKind: paneKind,
                    seq: seq
                )
            )
        )
    }

    private static func terminalActivityEvents(
        from subscriber: RecordingSubscriber<RuntimeEnvelope>
    ) async -> [TerminalActivityEvent] {
        RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot()).compactMap { record in
            guard case .terminalActivity(let event) = record.event else { return nil }
            return event
        }
    }

    private static func agentSettledPromotionCount(
        from subscriber: RecordingSubscriber<RuntimeEnvelope>
    ) async -> Int {
        await terminalActivityEvents(from: subscriber).count {
            if case .agentSettledActivityPromoted = $0 { return true }
            return false
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

    private func waitForReplacementSleepPair(
        clock: TestPushClock,
        scheduledAfter generation: Int
    ) async {
        await clock.waitForPendingSleepCount(atLeast: 2, fromGeneration: generation)
    }
}
