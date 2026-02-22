import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct NotificationReducerTests {
    @Test("critical events are emitted immediately")
    func criticalImmediate() async {
        let reducer = NotificationReducer()
        var iterator = reducer.criticalEvents.makeAsyncIterator()

        let envelope = makeEnvelope(
            seq: 1,
            event: .terminal(.bellRang)
        )
        reducer.submit(envelope)

        let received = await iterator.next()
        #expect(received?.seq == envelope.seq)
    }

    @Test("lossy events coalesce by key and latest wins")
    func lossyCoalesces() async {
        let reducer = NotificationReducer()
        var iterator = reducer.batchedEvents.makeAsyncIterator()
        let source = EventSource.pane(UUID())

        let first = makeEnvelope(
            seq: 1,
            source: source,
            event: .terminal(.scrollbarChanged(ScrollbarState(top: 1, bottom: 10, total: 100)))
        )
        let second = makeEnvelope(
            seq: 2,
            source: source,
            event: .terminal(.scrollbarChanged(ScrollbarState(top: 2, bottom: 11, total: 100)))
        )
        reducer.submit(first)
        reducer.submit(second)

        let batch = await iterator.next()
        #expect(batch?.count == 1)
        #expect(batch?.first?.seq == 2)
    }

    private func makeEnvelope(
        seq: UInt64,
        source: EventSource = .pane(UUID()),
        event: PaneRuntimeEvent
    ) -> PaneEventEnvelope {
        let clock = ContinuousClock()
        return PaneEventEnvelope(
            source: source,
            paneKind: .terminal,
            seq: seq,
            commandId: nil,
            correlationId: nil,
            timestamp: clock.now,
            epoch: 0,
            event: event
        )
    }
}
