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
}
