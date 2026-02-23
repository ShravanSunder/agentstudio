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
        let source = EventSource.pane(PaneId())

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

    @Test("critical events are ordered by visibility tier before emission")
    func criticalTierOrdering() async {
        let highTierPaneId = PaneId()
        let lowTierPaneId = PaneId()
        let resolver = TestVisibilityTierResolver(
            mapping: [
                highTierPaneId: .p0ActivePane,
                lowTierPaneId: .p3Background,
            ]
        )
        let reducer = NotificationReducer(tierResolver: resolver)
        var iterator = reducer.criticalEvents.makeAsyncIterator()

        reducer.submit(makeEnvelope(seq: 1, source: .pane(lowTierPaneId), event: .terminal(.bellRang)))
        reducer.submit(makeEnvelope(seq: 2, source: .pane(highTierPaneId), event: .terminal(.bellRang)))

        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.source == .pane(highTierPaneId))
        #expect(second?.source == .pane(lowTierPaneId))
    }

    @Test("lossy batch ordering prioritizes visibility tier")
    func lossyTierOrdering() async {
        let highTierPaneId = PaneId()
        let lowTierPaneId = PaneId()
        let resolver = TestVisibilityTierResolver(
            mapping: [
                highTierPaneId: .p0ActivePane,
                lowTierPaneId: .p3Background,
            ]
        )
        let reducer = NotificationReducer(tierResolver: resolver)
        var iterator = reducer.batchedEvents.makeAsyncIterator()

        reducer.submit(
            makeEnvelope(
                seq: 1,
                source: .pane(lowTierPaneId),
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 1, bottom: 10, total: 100)))
            )
        )
        reducer.submit(
            makeEnvelope(
                seq: 2,
                source: .pane(highTierPaneId),
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 1, bottom: 10, total: 100)))
            )
        )

        let batch = await iterator.next()
        #expect(batch?.count == 2)
        #expect(batch?.first?.source == .pane(highTierPaneId))
        #expect(batch?.last?.source == .pane(lowTierPaneId))
    }

    private func makeEnvelope(
        seq: UInt64,
        source: EventSource = .pane(PaneId()),
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

@MainActor
private final class TestVisibilityTierResolver: VisibilityTierResolver {
    private let mapping: [PaneId: VisibilityTier]

    init(mapping: [PaneId: VisibilityTier]) {
        self.mapping = mapping
    }

    func tier(for paneId: PaneId) -> VisibilityTier {
        mapping[paneId] ?? .p3Background
    }
}
