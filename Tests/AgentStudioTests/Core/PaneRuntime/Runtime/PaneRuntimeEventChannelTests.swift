import Dispatch
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
        let sourceKeyGate = BlockingRuntimeEnvelopeSourceKey()
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 1,
                sourceKey: sourceKeyGate.sourceKey
            ),
            performanceReporter: reporter
        )
        let subscription = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "runtimeChannelTransfer"
        )
        var iterator = subscription.makeAsyncIterator()
        let channel = makeChannel(paneEventBus: bus, reporter: reporter)

        emitBell(on: channel)
        await sourceKeyGate.waitUntilPostEntered()

        let outboundSnapshot = reporter.snapshot()
        #expect(outboundSnapshot.runtimeChannelOutboundPendingCount == 1)
        #expect(outboundSnapshot.eventBusActiveDeliveryDebt == 0)
        #expect(outboundSnapshot.totalPendingCount == 1)

        sourceKeyGate.allowPostToFinish()
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
        let sourceKeyGate = BlockingRuntimeEnvelopeSourceKey()
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 1,
                sourceKey: sourceKeyGate.sourceKey
            ),
            performanceReporter: reporter
        )
        let channel = makeChannel(paneEventBus: bus, reporter: reporter)

        emitBell(on: channel)
        await sourceKeyGate.waitUntilPostEntered()
        #expect(reporter.snapshot().runtimeChannelOutboundPendingCount == 1)

        channel.finishSubscribers()
        let finishingSnapshot = reporter.snapshot()
        #expect(finishingSnapshot.runtimeChannelOutboundPendingCount == 1)
        #expect(finishingSnapshot.runtimeChannelRetiredUndeliveredCount == 0)
        #expect(finishingSnapshot.totalPendingCount == 1)

        sourceKeyGate.allowPostToFinish()
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
        let sourceKeyGate = BlockingRuntimeEnvelopeSourceKey()
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 1,
                sourceKey: sourceKeyGate.sourceKey
            ),
            performanceReporter: reporter
        )
        let channel = makeChannel(paneEventBus: bus, reporter: reporter)

        emitBell(on: channel)
        await sourceKeyGate.waitUntilPostEntered()
        emitBell(on: channel)
        #expect(reporter.snapshot().runtimeChannelOutboundPendingCount == 2)

        channel.finishSubscribers()
        #expect(reporter.snapshot().runtimeChannelOutboundPendingCount == 2)

        sourceKeyGate.allowPostToFinish()
        await assertEventuallyAsync("only the cancelled buffered envelope should retire") {
            let snapshot = reporter.snapshot()
            return snapshot.runtimeChannelOutboundPendingCount == 0
                && snapshot.runtimeChannelRetiredUndeliveredCount == 1
        }
    }

    private func makeChannel(
        paneEventBus: EventBus<RuntimeEnvelope>,
        reporter: RuntimeDeliveryPerformanceReporter
    ) -> PaneRuntimeEventChannel {
        PaneRuntimeEventChannel(
            paneEventBus: paneEventBus,
            performanceReporter: reporter
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

private final class BlockingRuntimeEnvelopeSourceKey: @unchecked Sendable {
    private let postEnteredStream: AsyncStream<Void>
    private let postEnteredContinuation: AsyncStream<Void>.Continuation
    private let finishPostSemaphore = DispatchSemaphore(value: 0)

    init() {
        (postEnteredStream, postEnteredContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    deinit {
        postEnteredContinuation.finish()
        finishPostSemaphore.signal()
    }

    func sourceKey(_: RuntimeEnvelope) -> String {
        postEnteredContinuation.yield(())
        finishPostSemaphore.wait()
        return "blocked-runtime-channel-test"
    }

    func waitUntilPostEntered() async {
        var iterator = postEnteredStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func allowPostToFinish() {
        finishPostSemaphore.signal()
    }
}
