import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneRuntimeEventChannel")
struct PaneRuntimeEventChannelTests {
    @Test("emitted events arrive at the bus in sequence order")
    func emittedEventsReachBusInSequenceOrder() async {
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber()
        let paneId = PaneId.generateUUIDv7()
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            title: "Test"
        )
        let channel = PaneRuntimeEventChannel(paneEventBus: harness.bus)

        for index in 0..<10 {
            channel.emit(
                paneId: paneId,
                metadata: metadata,
                paneKind: .terminal,
                event: .terminal(.titleChanged("title-\(index)")),
                persistForReplay: false
            )
        }

        await assertEventuallyAsync(
            "bus subscriber should receive all emitted events",
            maxTurns: 5000
        ) {
            await subscriber.snapshot().count == 10
        }

        let envelopes = await subscriber.snapshot()
        let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: envelopes)
        #expect(paneEvents.count == 10)
        #expect(paneEvents.map(\.seq) == Array(1...10).map(UInt64.init))

        await subscriber.shutdown()
        channel.finishSubscribers()
        await assertBusDrained(harness.bus)
    }

    @Test("outbound debt transfers to EventBus debt without a false zero")
    func outboundDebtTransfersToEventBusDebt() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(performanceReporter: reporter)
        let outboundPostGate = RuntimeEnvelopeOutboundPostGate(paneEventBus: bus)
        let subscription = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "runtimeChannelTransfer"
        )
        var iterator = subscription.makeAsyncIterator()
        let channel = makeChannel(
            paneEventBus: bus,
            reporter: reporter,
            outboundPost: outboundPostGate.post
        )

        emitBell(on: channel)
        await outboundPostGate.waitUntilPostEntered()

        let outboundSnapshot = reporter.snapshot()
        #expect(outboundSnapshot.runtimeChannelOutboundPendingCount == 1)
        #expect(outboundSnapshot.eventBusActiveDeliveryDebt == 0)
        #expect(outboundSnapshot.totalPendingCount == 1)

        await outboundPostGate.allowPostToFinish()
        await assertEventuallyAsync("outbound custody should transfer to EventBus") {
            let snapshot = reporter.snapshot()
            return snapshot.runtimeChannelOutboundPendingCount == 0
                && snapshot.eventBusActiveDeliveryDebt == 1
                && snapshot.totalPendingCount == 1
        }

        _ = await iterator.next()
        #expect(reporter.snapshot().totalPendingCount == 0)
        channel.finishSubscribers()
    }

    @Test("finish keeps in-flight outbound debt pending until EventBus post completes")
    func finishKeepsInFlightOutboundDebtPendingUntilPostCompletes() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(performanceReporter: reporter)
        let outboundPostGate = RuntimeEnvelopeOutboundPostGate(paneEventBus: bus)
        let channel = makeChannel(
            paneEventBus: bus,
            reporter: reporter,
            outboundPost: outboundPostGate.post
        )

        emitBell(on: channel)
        await outboundPostGate.waitUntilPostEntered()
        #expect(reporter.snapshot().runtimeChannelOutboundPendingCount == 1)

        channel.finishSubscribers()
        let finishingSnapshot = reporter.snapshot()
        #expect(finishingSnapshot.runtimeChannelOutboundPendingCount == 1)
        #expect(finishingSnapshot.runtimeChannelRetiredUndeliveredCount == 0)
        #expect(finishingSnapshot.totalPendingCount == 1)

        await outboundPostGate.allowPostToFinish()
        await assertEventuallyAsync("completed in-flight post should leave no retired debt") {
            let snapshot = reporter.snapshot()
            return snapshot.runtimeChannelOutboundPendingCount == 0
                && snapshot.runtimeChannelRetiredUndeliveredCount == 0
        }
    }

    @Test("finish retires only buffered envelopes after an in-flight post completes")
    func finishRetiresOnlyBufferedOutboundDebt() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(performanceReporter: reporter)
        let outboundPostGate = RuntimeEnvelopeOutboundPostGate(paneEventBus: bus)
        let channel = makeChannel(
            paneEventBus: bus,
            reporter: reporter,
            outboundPost: outboundPostGate.post
        )

        emitBell(on: channel)
        await outboundPostGate.waitUntilPostEntered()
        emitBell(on: channel)
        #expect(reporter.snapshot().runtimeChannelOutboundPendingCount == 2)

        channel.finishSubscribers()
        #expect(reporter.snapshot().runtimeChannelOutboundPendingCount == 2)

        await outboundPostGate.allowPostToFinish()
        await assertEventuallyAsync("only the cancelled buffered envelope should retire") {
            let snapshot = reporter.snapshot()
            return snapshot.runtimeChannelOutboundPendingCount == 0
                && snapshot.runtimeChannelRetiredUndeliveredCount == 1
        }
    }

    private func makeChannel(
        paneEventBus: EventBus<RuntimeEnvelope>,
        reporter: RuntimeDeliveryPerformanceReporter,
        outboundPost: @escaping PaneRuntimeEventChannel.OutboundPost
    ) -> PaneRuntimeEventChannel {
        PaneRuntimeEventChannel(
            paneEventBus: paneEventBus,
            performanceReporter: reporter,
            outboundPost: outboundPost
        )
    }

    private func emitBell(on channel: PaneRuntimeEventChannel) {
        let paneId = PaneId.generateUUIDv7()
        channel.emit(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                contentType: .terminal,
                title: "Test"
            ),
            paneKind: .terminal,
            event: .terminal(.bellRang),
            persistForReplay: false
        )
    }
}

private actor RuntimeEnvelopeOutboundPostGate {
    private let paneEventBus: EventBus<RuntimeEnvelope>
    private var postEntryWaiters: [CheckedContinuation<Void, Never>] = []
    private var postReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasPostEntered = false
    private var isPostReleased = false

    init(paneEventBus: EventBus<RuntimeEnvelope>) {
        self.paneEventBus = paneEventBus
    }

    func post(_ envelope: RuntimeEnvelope) async -> EventBus<RuntimeEnvelope>.PostResult {
        if !hasPostEntered {
            hasPostEntered = true
            let entryWaiters = postEntryWaiters
            postEntryWaiters.removeAll(keepingCapacity: false)
            for entryWaiter in entryWaiters {
                entryWaiter.resume()
            }

            if !isPostReleased {
                await withCheckedContinuation { continuation in
                    postReleaseWaiters.append(continuation)
                }
            }
        }

        return await paneEventBus.post(envelope)
    }

    func waitUntilPostEntered() async {
        guard !hasPostEntered else { return }
        await withCheckedContinuation { continuation in
            postEntryWaiters.append(continuation)
        }
    }

    func allowPostToFinish() {
        guard !isPostReleased else { return }
        isPostReleased = true
        let releaseWaiters = postReleaseWaiters
        postReleaseWaiters.removeAll(keepingCapacity: false)
        for releaseWaiter in releaseWaiters {
            releaseWaiter.resume()
        }
    }
}
